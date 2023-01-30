# dhall-terraform-libgen

 [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/dhall-terraform/dhall-terraform)

`dhall-terraform-libgen` uses terraform's provider schema to generate Dhall types & defaults
for each `resource`, `data_source` & `provider` block. 

This allows us to use Dhall to create cloud resources instead of HCL & avoid its
limitations.

### Installation

You can use one of `cabal-install` or `nix` to build and install the
project.

### Usage

- Use terraform to generate a provider's schema
  See [here](https://www.terraform.io/docs/commands/providers/schema.html) how
  you can generate the provider's schema.
- Use `dhall-terraform-libgen` to generate the types of your provider. 
- Write the resources in Dhall. Checkout the [examples](./examples).
- Use `dhall-to-json` to generate terraform's [JSON syntax][terraform_json_syntax]
- Continue with `terraform` operations as normal.

### Usage Example for AWS

```bash
nix develop # wait for shell
cabal build # wait for build
source dtf # get the "dhall terraform" helper function in scope FIXME: This should be done by nix
HERE=$(pwd)
DEV_DIR="ex"  # Make place for us to write dev stuff.
              # Choose your own folder outside if you want.
              # Assumed by subsequent code to be a _relative_ directory
mkdir -p "$DEV_DIR"/schemas # Make a place to put the aws schema
mkdir -p "$DEV_DIR"/lib # Make a place to put the generated Dhall files
mkdir -p "$DEV_DIR"/src # Make a place to put your resources
cd tf/aws # there is an example gen.tf here that does nothing except pull in hashicorp/aws
terraform init
terraform providers schema -json > schema.json
cd "$HERE" # change back to the root of this project
mv tf/aws/schema.json "$DEV_DIR"/schemas/aws.json
cp -r static/ "$DEV_DIR"/static/ # copy the util.dhall file to where the lib can find it when generated
cabal run -- dhall-terraform-libgen -f "$DEV_DIR"/schemas/aws.json -p registry.terraform.io/hashicorp/aws -o "$DEV_DIR"/lib
cd "$DEV_DIR"/src
$EDITOR main.dhall # edit your file
dtf main.dhall # generate and validate the terraform you made
# terraform plan ...
# etc
```

### AWS example

Example using the generated resources from the AWS provider.

```dhall
let Prelude =
      https://raw.githubusercontent.com/dhall-lang/dhall-lang/master/Prelude/package.dhall

-- Get the correct type needed for Terraform's JSON syntax.
let jsonRes = λ(a : Type) → { mapKey : Text, mapValue : a }

-- Create a JSON serialized resource given its name and type.
let mkRes =
        λ(a : Type)
      → λ(name : Text)
      → λ(body : a)
      → Prelude.JSON.keyValue a name body

-- Import the necessary resources.
let AwsProvider =
      https://raw.githubusercontent.com/mujx/dhall-terraform/99a96658642aef74f0b01c0da73f2c9a07171f52/lib/aws/provider/provider.dhall

let AwsS3Bucket =
      https://raw.githubusercontent.com/mujx/dhall-terraform/99a96658642aef74f0b01c0da73f2c9a07171f52/lib/aws/resources/aws_s3_bucket.dhall

let defaultRegion = "us-east-1"

let Bucket = { region : Text, name : Text }

let buckets =
        [ { region = defaultRegion, name = "images" }
        , { region = defaultRegion, name = "files" }
        ]
      : List Bucket

let toBucketResource
    : Bucket → jsonRes AwsS3Bucket.Type
    =   λ(bkt : Bucket)
      → mkRes
          AwsS3Bucket.Type
          bkt.name
          AwsS3Bucket::{
          , tags = Some [ { mapKey = "content", mapValue = bkt.name } ]
          , region = Some defaultRegion
          }

let awsProvider =
      mkRes
        AwsProvider.Type
        "aws"
        AwsProvider::{ region = defaultRegion, version = Some "2.34.0" }

in  { provider = [ awsProvider ]
    , resource =
        { aws_s3_bucket =
            Prelude.List.map
              Bucket
              (jsonRes AwsS3Bucket.Type)
              toBucketResource
              buckets
        }
    }
```

### Options

```
dhall-terraform-libgen :: v0.3.1

Usage: dhall-terraform-libgen (-f|--schema-file SCHEMA) (-p|--provider-name PROVIDER)
                       [-o|--output-dir OUT_DIR]
  Generate Dhall types from Terraform resources

Available options:
  -h,--help                Show this help text
  -f,--schema-file SCHEMA  Terraform provider's schema definitions
  -p,--provider-name PROVIDER
                           Which provider's resources will be generated
  -o,--output-dir OUT_DIR  The directory to store the generated
                           files (default: "./lib")
```

[terraform_json_syntax]: https://www.terraform.io/docs/configuration/syntax-json.html

### Troubleshooting

If you get an error when running `cabal run -- dhall-terraform-libgen ...` that looks like:

```text

```
