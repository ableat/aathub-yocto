<h1 align="center">
  <a href="https://github.com/ableat/aathub-yocto"><img src="docs/imgs/brick.png" alt="aathub yocto" width="200"></a>
  <!-- https://pixabay.com/en/letter-alphabet-parts-reading-1546830/ -->
  <br>
  aathub yocto
  <br>
</h1>

<h4 align="center">A build system without any of the bullshit</h4>

<p align="center">
  <a href="https://app.shippable.com/github/ableat/aathub-yocto">
    <img src="https://api.shippable.com/projects/59e7522854c135070007087a/badge?branch=master"
         alt="Status">
  </a>
</p>

<br>

## Synopsis

Setups a development environment, compiles a [yocto](https://www.yoctoproject.org/)-based image, and optionally uploads the results to [S3](https://aws.amazon.com/s3/).

## Resources

Don't know anything about yocto? Read these:
  - [yocto wiki](https://wiki.yoctoproject.org/wiki/Main_Page)
  - [intro to yocto slides](https://docs.google.com/presentation/d/1LmI3mHoD_Dzl8wplIYcUBrFF8BzDb_EadTvfbnpSK7Q/edit#slide=id.p4)
  - [advanced yocto slides](https://docs.google.com/presentation/d/1HoDtyN5SzlmuTN47ab4Y7w_i6c_VEW6EBUD944ntf38/edit#slide=id.p4)

## How to use

### Simple

Kick off the build process with the following command:
```
./bootstrap.sh
```

### Advanced

Sourcing `bootstrap.sh` is only necessary if passing in the `-s` param.

```
. ./bootstrap.sh -v -s -u bender -b /path/to/directory
```

Here's a breakdown:

- `-v` enable verbose output
- `-s` upload compiled results to S3
- `-u bender` is an arbitrary user, used to execute `bitbake`. If the user doesn't exist one is created
- `-b /path/to/directory` parent directory where compilation occurs (the default is `/tmp`)

<br>

For the most up-to-date instructions run the following command:
```
./bootstrap.sh -h
```

## Testing

If `oe-init-build-env` isn't sourced, do so now
```
runqemu path/to/kernel-image.bin path/to/root-filesystem.ext3
```

## Things to consider

- The build takes 2 hours to compile on a `c4.2xlarge`, and requires upwards of 50GB of free space.

- This has been sucessfully tested on ubuntu/debian and fedora.

- We base64 a few files used in shippable's secure variables. Use the following command `base64 -w 0 /path/to/file`

- The build system depends on `meta-aatlive`, a closed-source bitbake layer

- PR builds will fail since secure variables aren't initalized. You have been warned... 
