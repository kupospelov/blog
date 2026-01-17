---
title: Bootstrapping rootless containers with Ansible
date: 2026-01-17T15:15:50+02:00
---

Some deployments can be easily automated with SSH and shell scripts, but once a deployment reaches a certain (not-so-big) size, one may start searching for easier to manage alternatives. In this post, I will summarize what I ended up using so far and describe an automated way to bring up a machine with rootless Podman containers using the official [nginx](https://hub.docker.com/_/nginx) image as an example.

<!--more-->

# Podman

First, let's cover the container configuration, and then move to the configuration of the managed node. For simplicity, this part assumes that you run a Linux system and have Podman installed.

## Why Podman?

I prefer Podman for a couple of reasons:

1. Daemonless and rootless approach that reduces the attack surface.
2. Systemd integration that simplifies the whole setup. You can basically run your containers as (almost) regular systemd services.

I can also recommend the book [Podman in Action](https://developers.redhat.com/e-books/podman-action) that covers Podman in more detail.

## Quadlets

Nowadays systemd supports [quadlets](https://www.redhat.com/en/blog/quadlet-podman) that make running containers somewhat easier compared to the more manual [podman systemd generate](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html) approach. The idea is that you can describe Podman flags in the `[Container]` section of the quadlet, and systemd will generate a service unit file for it. You can also enable automatic updates using `AutoUpdate=registry` and systemd will be updating the container image for you. Nice!

We can create `~/.config/containers/systemd/nginx.container` with the following contents:

```systemd
[Container]
Image=docker.io/library/nginx:latest
AutoUpdate=registry
PublishPort=8080:80
Volume=%h/nginx/content:/var/www/html:Z,ro
Volume=%h/nginx/nginx.conf:/etc/nginx/nginx.conf:Z,ro

[Service]
Restart=always

[Install]
WantedBy=default.target
```

This container needs a config. Let's create the simplest `~/nginx/nginx.conf`:

```nginx
worker_processes auto;

events {
	worker_connections 64;
}

http {
	server {
		server_name localhost;
		listen 80;
		listen [::]:80;

		location / {
			root /var/www/html;
			index index.html;
		}
	}
}
```

We also need some content to serve, so let's put the following `index.html` in `~/nginx/content/`:

```html
<h1>Hello from Podman!</h1>
```

Finally, before our user can run the container, we need to allocate user and group id ranges. You can read more in the rootless Podman [tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md), but to keep this post short you can just run this command to allocate the `100000-165535` id ranges for your user in `/etc/subuid` and `/etc/subgid`:

```sh
usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
```

...and that's almost it! To test the container locally, run these commands:

```sh
systemctl --user daemon-reload
systemctl --user start nginx
```

The first command generates a service file based on the quadlet, and the second one starts the new service. If the service for some reason fails to start, you can use `journalctl -xe` to see the most recent failures in the journal.

You should now see the index page if you open [http://localhost:8080](http://localhost:8080).

# Ansible

Now that we have a working local setup, we can replicate it on a managed node. This section assumes that the host runs Debian 13, but except for the `apt` module the configuration should be mostly the same for any other distribution.

# Why Ansible?

[Ansible](https://docs.ansible.com/) is by no means a new tool, but it's still maintained and I find it intuitive to use for simple use cases like this. My first attempt at automating setting up a new VM involved a few shell scripts, and when I replaced all of them with a single Ansible playbook, the setup has become much simpler.

Another seemingly good option is [Butane](https://coreos.github.io/butane/getting-started/). I like the idea of running a minimal Fedora CoreOS, but unlike Debian not every VPS provider has a default image for it, and the instructions to install it manually look a bit tedious. Maybe I'll try it some other time and write a post about how to achieve the same with CoreOS and Butane :)

# Playbook

Ansible allows you to describe the configuration as a YAML [playbook](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_intro.html). Playbooks use [modules](https://docs.ansible.com/projects/ansible/2.9/modules/list_of_all_modules.html) to describe the end state, e.g. a copied file or installed package.

Playbooks can be run using `ansible-playbook <playbook.yaml> -u <user> -i <inventory>`, where `user` is the user to use and `inventory` can either be an [inventory file](https://docs.ansible.com/projects/ansible/devel/inventory_guide/intro_inventory.html) or a comma-separated list of hosts, e.g. `1.2.3.4,` (note a comma in the end!).

[Here](example.yaml) is the complete example. The rest of the post explains it section by section. I'm not going into too much detail though, refer to the official [documentation](https://devdocs.io/ansible/collections/ansible/builtin/index) to clarify specific module options.

Let's start with defining a playbook that will install the required Debian packages:

```yaml
- name: Install nginx
  hosts: all
  become: true

  vars:
    nginx_user: nginx
    nginx_home: /home/nginx

  tasks:
    - name: Install packages
      ansible.builtin.apt:
        pkg:
          - podman
          - systemd-container
        state: present
        update_cache: true
        cache_valid_time: 3600
      tags: packages
```

Now, let's create a new user. Here we also allocate the id ranges and enable lingering to make sure the user services start after a reboot:

```yaml
    - name: Create user
      ansible.builtin.user:
        name: "{{ nginx_user }}"
        state: present
        create_home: true
        home: "{{ nginx_home }}"
        shell: /sbin/nologin
        system: true
      tags: user

    - name: Allocate user ids
      ansible.builtin.lineinfile:
        path: /etc/subuid
        line: "{{ nginx_user }}:100000:65536"
        create: true
      tags: user

    - name: Allocate group ids
      ansible.builtin.lineinfile:
        path: /etc/subgid
        line: "{{ nginx_user }}:100000:65536"
        create: true
      tags: user
    
    - name: Enable lingering
      ansible.builtin.command:
        cmd: "loginctl enable-linger {{ nginx_user }}"
      changed_when: false
      tags: user
```

Once we have the user configured, we can copy all the configuration files from the control node to the remote user's home directory:

```yaml
    - name: Create directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: "{{ nginx_user }}"
        group: "{{ nginx_user }}"
        mode: '0755'
      loop:
        - "{{ nginx_home }}/.config/containers/systemd"
        - "{{ nginx_home }}/nginx/content"
      tags: config

    - name: Copy files
      ansible.builtin.copy:
        src: "{{ item.src }}"
        dest: "{{ item.dest }}"
        owner: "{{ nginx_user }}"
        group: "{{ nginx_user }}"
        mode: '0644'
      loop:
        - src: ~/nginx/nginx.conf
          dest: "{{ nginx_home }}/nginx/nginx.conf"
        - src: ~/nginx/content/index.html
          dest: "{{ nginx_home }}/nginx/content/index.html"
        - src: ~/.config/containers/systemd/nginx.container
          dest: "{{ nginx_home }}/.config/containers/systemd/nginx.container"
      tags: config
```

Finally, we can reload daemons and start the service:

```yaml
    - name: Reload daemons
      ansible.builtin.command:
        cmd: "systemctl --machine={{ nginx_user }}@ --user daemon-reload"
      changed_when: false
      tags: service

    - name: Start service
      ansible.builtin.command:
        cmd: "systemctl --machine={{ nginx_user }}@ --user start nginx"
      changed_when: false
      tags: service
```

Note that Ansible has a [systemd module](https://docs.ansible.com/projects/ansible-core/2.13/collections/ansible/builtin/systemd_module.html). However, I found it very cumbersome to use for the user scope. It requires setting the `XDG_RUNTIME_DIR` environment variable that contains a user id. It's possible to query it (e.g. using `ansible.builtin.getent`), but I think it's way easier just to call `systemctl --machine=nginx@`.

If your firewall does not block port `8080`, you should be able to see the page served by your server.

# Summary

That's finally it! You should now have a working rootless setup that supports automatic updates and can be easily re-created on a new Debian machine.
