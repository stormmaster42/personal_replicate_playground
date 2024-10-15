# Personal Replicate Image Generation Playground

A simple personal image generator web app based on Replicate, intended for local use.

![image](https://github.com/user-attachments/assets/88108bde-d69e-46c0-853d-306ee3bf5c0f)

**Note**

A replicate.com account is required.
It does not include authentication - do not run in the cloud!

**Why?**

* Not enough GPU to run image gen models locally?
* Freedom to choose models and tinker with settings.
* A simple UI and direct access to images locally.

**Features & Opinionated Settings**

* Always generates the highest resolution
* Upscales and applies face-fixing
* Choose aspect ratio 1:1, 16:9, 9:16
* One-click prompt enhancement (using replicate llama)

**Installation**

1. Clone the repo
2. Build the Docker image: `docker build .`
3. Set the Replicate API token as an environment variable: `export REPLICATE_API_TOKEN=<replicate key: r8_.....>`
4. Run the Docker container: `docker run -v ./cache:/app/cache -e REPLICATE_API_TOKEN --name image_gen -d -p 8080:8080 image_gen`

**Details**
* `./cache` is the folder where the app stores images and metadata (in a JSON file for now)

**About**

* Deliberately using simple tech - Ruby, Sinatra, and Docker - to keep things easy to understand and maintainable.
* This app is not intended for production use, but rather as a personal image generator for local use.
* Use at your own risk.
