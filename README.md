## 🐫 on AWS Lambda

OCaml runtime for AWS Lambda

## Requirements

* OCaml 4.07
* opam
* dune
* Docker
* an AWS account

## Building

Make sure Docker is installed and run `build.sh`.

On the first run the build process is going to take a while to prepare a Docker container with the OCaml environment.

Once the build is done a `bootstrap.zip` archive containing the runtime is produced.

## Deploying

From the AWS Lambda console create a new function.

Select _Author from scratch_ and _Provide your own bootstrap_ as **Runtime**.

Finally in the **Function code** panel upload the `bootstrap.zip` archive and _Save_ the function.

