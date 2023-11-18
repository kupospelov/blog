---
title: My unoriginal approach to manage dotfiles
date: 2020-06-23T23:30:00+02:00
---
After I had to set up a few machines this year, I finally realized that I should have a tool to version and quickly restore my configuration files. This post is about what I came up with.

<!--more-->

My `$HOME` is a git repository similar to one described in the [post](https://drewdevault.com/2019/12/30/dotfiles.html) by Drew DeVault. I like this approach, because there is no need in symlinks and git is a nice and familiar tool to use. My setup is a little bit different though.

In fact, my `$HOME` contains two git repositories: one for general-purpose public dotfiles and one for private dotfiles. I do this by specifying `--git-dir` and `--work-tree`, inspired by [this article](https://www.atlassian.com/git/tutorials/dotfiles). For convenience, I created two different shell aliases for these commands.

The general-purpose part defines the file structure and can be shared in a public [repository](https://git.sr.ht/~kupospelov/dotfiles). This is the place to store the files for _all_ my machines. This is also almost everything that I need on my personal ones.

The private part contains files that are specific to the organization I am working at, and that is the reason to store them in a separate private repository. This repository can generally have more than one branch to store files for different machine types.

I find storing machine-specific configuration in git a bit cumbersome, so parameters like output scale or touchpad sensitivity are not versioned. My dotfiles contain so few such files that I do not care if I have to recreate them manually at some point.

The tricky thing is to refactor the configuration files to split them into public and private ones. There is no one-fits-all solution to this problem. Ideally, you would want to use `config.d` directories to store the pieces that are different, but this may not always be possible. In `.bashrc`, I use a simple `for` loop which iterates over all files in `~/.bashrc.d` and sources them. In the case of sway, the `include` command makes it possible to put some pieces of the configuration outside of the main config file.

In the end, restoring a complete configuration in this setup boils down to cloning the shared dotfiles and the proper private branch, and then to optional per-device customizations.
