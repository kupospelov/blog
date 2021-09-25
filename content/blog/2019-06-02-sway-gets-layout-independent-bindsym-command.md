---
title: Sway gets layout-independent bindsym command
date: 2019-06-02T13:12:00+03:00
---
The default behavior of the `bindsym` command in Sway is a major pain point for users with several configured keyboard layouts. The command literally binds actions to keysyms, which means that your shortcuts constantly change their position or may not work at all.

<!--more-->

What makes it look even more weird is that in i3 `bindsym` _does_ work consistently in any layout, because i3 simply translates the specified keysyms into keycodes. You can even specify which layout should be used for the translation using `Group[1-4]`.

The topic of input processing is far more complex than I could imagine, mostly because different people have _very_ different opinions about how it should be implemented. The very idea to change the meaning of the `bindsym` command triggered a lot of back-and-forth discussion with quite a few people involved.

The process took some time, but in the end we finally got a solution that should work for everyone. With the new `--to-code` flag, the behavior of Sway's `bindsym` becomes roughly equivalent to that of i3. This is not as tedious as you might think, because you can specify the flag only once per block of bindings:
```
bindsym --to-code {
    $mod+Return exec $term
    $mod+Shift+c reload
    # etc
}
```

A few points regarding the current implementation:
* The translation only uses the first configured layout. A change in the input configuration can trigger re-translation of the configured bindings.
* In case the translation fails, the binding will work as an ordinary `bindsym`, and a warning will be logged. We cannot fail the command in this case, because `input` and `bindsym` commands can be in any order (and cannot be sorted, in case of IPC), so the relevant input configuration may not be available yet.
* In case a keysym cannot be resolved into a single keycode, the translation will fail. This should not be a frequent use-case, so the complexity it introduces is not worth it at this point.

The feature will appear in Sway 1.1, which is going to be released soon. You can also get an RC build and try it out now.
