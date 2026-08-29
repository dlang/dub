Specifying `$DFLAGS` in the environment no longer overwrites dub-added flags

When the `$DFLAGS` variable was present in the environment (even if
empty) Dub would stop itself from adding any flags implied by the
build type. This can lead to serious issues with `dub test` not
running unittests, like in the below example:

```
$ DFLAGS= dub test # this does not run any unittests
```

This has been changes and now, the `$DFLAGS` variable is simply
appended to the dub generated build flags.

If you rely on the old behavior you can pass `--build=plain` to `dub`,
in addition to specifying your custom flags in `$DFLAGS`.
