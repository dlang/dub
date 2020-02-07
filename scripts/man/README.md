1) Build
--------

```shell
./gen_man.d
```

2) Preview
----------

On Linux:
```shell
man -l dub.1
```

On OSX:
```shell
mkdir -p man1
mv *.1 man1
man -M . dub
```
