<h1 align="center">
  <a href="https://github.com/ableat/aathub-yocto"><img src="docs/imgs/brick.gif" alt="aathub yocto" width="200"></a>
  <br>
  aathub yocto
  <br>
</h1>

<h4 align="center">A build system without any of the bullshit</h4>

<br>


## How to use

### Simple

Kick off the build process with the following command:
```
./bootstrap.sh
```

### Advanced

```
./bootstrap.sh -v -u bender -b /path/to/directory
```

`bender` *is an arbitrary user. the name doesn't matter*

<br>

For assistance run the following command:
```
./bootstrap.sh -h
```

## Things to consider

The build takes 4+ hours (depending on the machine) to complete, and requires upwards of 50GB of space.

This has been sucessfully tested on ubuntu/debian and fedora.
