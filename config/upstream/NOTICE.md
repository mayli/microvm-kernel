# Vendored Firecracker guest configs

These files are copied from the Firecracker project so that the kernel build
does not depend on a moving branch.

- Project: <https://github.com/firecracker-microvm/firecracker>
- Commit: `4e65d4309c355925872b9d3006f18eef96653645`
  (2026-11-18)
- Path: `resources/guest_configs/`

Files and SHA-256:

```text
ba22401a0c7292a4c024ebcd10a562d4a1f1bfd2faed671406d3b159c0cf5215  microvm-kernel-ci-x86_64-6.18.config
a271fc11701c175b16d39f2493873eed527028a846c4da645ac4abc1728699df  ci.config
ef237613d79df5f9df03ff0cb873a43c9558245081824568c35b074d44d3ebd6  efi.config
```

Firecracker is licensed under Apache-2.0. See `LICENSE-Apache-2.0` in this
directory.

`microvm-kernel-ci-x86_64-6.18.config` is the full base config.
`ci.config` and `efi.config` are fragments applied on top of it; they are not
standalone configs.
