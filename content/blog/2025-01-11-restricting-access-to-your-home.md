---
title: Restricting access to your $HOME
date: 2025-01-11T12:04:50+02:00
---

From time to time I play some (mostly older) Steam games, which implies running closed-source binaries and hoping that they will not exploit the unrestricted access to your system. This has always been a little disturbing, but fortunately there are simple ways to decrease this risk, at least when it comes to your home directory.

<!--more-->

As far as I know, unless we talk about more complicated options like AppArmor or SELinux, there are two general approaches to limit access to your personal files in Linux. Let's explore them both.

# Running the binary as another user

In the pre-Wayland times I had a working setup in which my web browser was running as a different user. In this case standard Unix file access permissions could be used to prevent that user from having access to my primary user files.

I tried using a similar approach this time as well, but found out that for Wayland/XWayland the setup became more involving. You can find more details in the [discussion](https://forums.gentoo.org/viewtopic-t-1133520-start-0-postdays-0-postorder-asc-highlight-.html) on the Gentoo forums, here I'll just summarize the approach, assuming the new user is `steam`.

## Wayland

To run Wayland applications, the new user must have access to the Wayland socket. Your primary user owns it, but you can use `setfacl` to share it with `steam`:

```sh
setfacl -m steam:r-x -- "$XDG_RUNTIME_DIR"
setfacl -m steam:rwx -- "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
```

## XWayland

To share access to the X server, you can configure mcookies:

```sh
touch ~/.Xauthority
xauth add "$DISPLAY" . "$(mcookie)"
```

You can list mcookies by running `xauth list`. Make sure to add the same mcookie to the `.Xauthority` of the `steam` user so that it can authenticate.

This also requires setting the `-auth` argument for `Xwayland`. For wlroots-based compositors you can set `WLR_XWAYLAND` to run a custom script that will start `Xwayland` with the `-auth` argument that points to the created `.Xauthority` file. 

I found this setup a little bit too clumsy for my use case, so I decided to look into sandboxing.

# Running the binary in a sandbox

The simplest option to run a sandboxed Steam would probably be Flatpak, however there are a few things I do not like about it, most of them are covered in the [Flatpak Is Not the Future](https://ludocode.com/blog/flatpak-is-not-the-future) post. Specifically, Steam _already_ uses sandboxing to replace the system libraries with its own. So, it makes little sense to use the heavy Flatpak environment, since the Steam runtime will re-mount almost everything anyway. It will not re-mount `$HOME` though, and this is what I want to fix.

As it turns out, there are at least two lightweight sandboxing options: [firejail](https://github.com/netblue30/firejail) and [bubblewrap](https://github.com/containers/bubblewrap). In fact, Steam comes with its own [bubblewrap](https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/tree/main/subprojects/bubblewrap?ref_type=heads) that it uses to prepare the runtime. I did not experiment with `firejail` much and chose `bubblewrap` as a simpler option that happened to be already installed on my system as a dependency of another package.

I came up with the following [wrapper](https://git.sr.ht/~kupospelov/dotfiles/tree/700f572b63a66e7eee2f708b269fac39322417e7/item/.local/bin/sandbox). Note that `/mnt/sandbox` is mounted as `$HOME`:

```sh
exec /usr/bin/bwrap \
  --unshare-pid \
  --ro-bind /{,} \
  --dev-bind /dev{,} \
  --proc /proc \
  --tmpfs /dev/shm \
  --tmpfs /tmp \
  --bind "$XDG_RUNTIME_DIR"{,} \
  --bind /mnt/sandbox "$HOME" \
  --ro-bind "$HOME/.local/bin"{,} \
  --ro-bind "$HOME/.Xauthority"{,} \
  --ro-bind /tmp/.X11-unix/X0{,} \
  "$@"
```

Compared to the previous approach, I obviously do not need to share anything, since the user is the same, and this simplifies the setup quite a bit.

In terms of performance, I did not notice any issues. I suspect that the sandbox may even be faster in some cases, since my home directory is encrypted and `/mnt/sandbox` is not, but I did not really measure that.
