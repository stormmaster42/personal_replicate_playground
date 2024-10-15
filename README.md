# Personal Replicate Image Generation Playground

A simple personal image generator web app based on Replicate, intended for local use.

**Note**

A replicate.com account is required.
Does not include authentication - do not run in the cloud!

**Why?**

* Not enough GPU to run image gen models locally?
* Freedom to choose models and tinker with settings.
* A simple UI and direct access to images locally.

**Features & Opinionated Settings**

* Always generates highest resolution
* Upscales and applies face fixing
* Choose aspect ratio 1:1, 16:9, 9:16
* One click prompt enhancement (using replicate llama)

**Installation**

1. Clone the repo
2. Build the Docker image: `docker build .`
3. Set the Replicate API token as an environment variable: `export REPLICATE_API_TOKEN=<replicate key: r8_.....>`
4. Run the Docker container: `docker run -v ./cache:/app/cache -e REPLICATE_API_TOKEN --name image_gen -d -p 8080:8080 image_gen`

**Details**
* `./cache` is the folder where the app stores images and meta data (in a json file for now)

**About**

* Deliberately using simple tech - Ruby, Sinatra, and Docker - to keep things easy to understand and maintainable.
* This app is not intended for production use, but rather as a personal image generator for local use.
* Use at your own risk.
