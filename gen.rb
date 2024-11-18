#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'sinatra'
  gem 'http'
  gem 'json'
  gem 'rackup'
end

require 'sinatra'
require 'http'
require 'json'
require 'digest'
require 'fileutils'
require 'cgi'
require 'yaml'

# Set the desired port number
set :port, 8080 # Change this to the port number you want

set :inline_templates, true
set :public_folder, File.join(__dir__, 'public')

# Load the API token from the environment variable
REPLICATE_API_TOKEN = ENV['REPLICATE_API_TOKEN']
if REPLICATE_API_TOKEN.nil? || REPLICATE_API_TOKEN.empty?
  abort('Error: REPLICATE_API_TOKEN environment variable is not set.')
end

MODELS = YAML.load_file(File.join(__dir__, 'models.yaml'), symbolize_names: true)[:models]

# Directory where images will be cached
CACHE_DIR = File.join(__dir__, 'cache')
FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

# Filepath for the metadata file
METADATA_FILE = File.join(CACHE_DIR, 'metadata.json')

# Function to load metadata from file
def metadata
  @metadata ||=
    if File.exist?(METADATA_FILE)
      JSON.parse(File.read(METADATA_FILE))
    else
      {}
    end
end

# Function to save metadata to file
def save_metadata
  # TODO: ensure only one writer: with lock
  File.open("#{METADATA_FILE}.lock", File::CREAT) do |f|
    f.flock(File::LOCK_EX)

    File.open(METADATA_FILE, 'w') do |f|
      f.write(JSON.pretty_generate(metadata))
    end
  ensure
    f.flock(File::LOCK_UN)
  end
end

# Function to load the last 100 images from the cache
def load_last_images(filename = nil)
  files = Dir.glob("#{CACHE_DIR}/*.png")
             .sort_by { |file| File.mtime(file) }
             .map { |file| File.basename(file) }
  files = files[0..files.index(filename) - 1] if files.index(filename)

  files.reverse.first(100).map do |file|
    {
      file:,
      prompt: metadata.dig(file, 'prompt'),
      model: metadata.dig(file, 'prediction', 'model')
    }
  end
end

# Home route with prompt input form
get '/' do
  @metadata = metadata
  erb :index
end

def forward_to_replicate(input, model)
  puts input
  response = http.post('https://api.replicate.com/v1/predictions',
                       json: {
                         version: model,
                         input:
                       })

  halt 500, "Failed to retrieve prediction: #{response.body}" unless response.status.success?

  JSON.parse(response.body)
end

# cache the latest model version id
def get_latest_model_version_id(model_name)
  @get_latest_model_version_id ||= Hash.new do |h, k|
    h[k] = get_latest_model_version_id!(k)
  end

  @get_latest_model_version_id[model_name]
end

# Helper method to get the latest version of a model by name
def get_latest_model_version_id!(model_name)
  response = http.get("https://api.replicate.com/v1/models/#{model_name}")

  if response.status.success?
    model_info = JSON.parse(response.body)
    model_info['latest_version']['id']

  else
    halt 500, { "error": "Failed to retrieve model version for #{model_name}." }.to_json
  end
end

# Helper method to poll for completion
def poll_for_completion(prediction_id)
  loop do
    response = http.get("https://api.replicate.com/v1/predictions/#{prediction_id}")
    result = JSON.parse(response.body)
    return result if result['status'] == 'succeeded' || result['status'] == 'failed'

    sleep(2)
  end
end

def start_and_get_result(input, version, image_filename)
  prediction = forward_to_replicate(input, version)

  prediction_id = prediction['id']

  # Poll for the result until it's ready
  result = poll_for_completion(prediction_id)
  output = result['output']
  # output is string or array => get the first element if it's an array
  result_url = output.is_a?(Array) ? output.first : output

  # Download the image from the result URL
  image_data = HTTP.get(result_url).body
  File.open(image_filename, 'wb') do |file|
    file.write(image_data)
  end

  result
end

def dimension(aspect_ratio, longest_side = 2048)
  width, height = aspect_ratio.split(':').map(&:to_f)
  if width > height
    [longest_side, (longest_side * height / width).round]
  else
    [(longest_side * width / height).round, longest_side]
  end
end

# Create a filename-safe summary of the prompt, limited to 200 characters
def filename_for_prompt(prompt)
  safe_prompt = CGI.escape(prompt)[0..200].gsub(/\s+/, '_').gsub(/\W+/, '').downcase
  timestamp = Time.now.strftime('%Y%m%d%H%M%S')
  "#{timestamp}_#{safe_prompt}.png"
end

def http
  HTTP.auth("Token #{REPLICATE_API_TOKEN}")
end

# Async image generation route
post '/generate' do
  prompt = params[:prompt]
  image_filename = File.join(CACHE_DIR, filename_for_prompt(prompt))
  model = MODELS[params[:model].to_sym]
  negative_prompt = params[:negative_prompt]
  data = {
    prompt:
  }

  # If the image isn't cached, make the API request
  unless File.exist?(image_filename)
    version = get_latest_model_version_id(model[:model])
    trigger = model[:trigger]
    dimension = dimension(params[:aspect_ratio], model[:max_width])
    prompt_and_trigger = trigger ? "#{prompt}; in the style of #{trigger}" : prompt
    input = {}
    input.merge!(model[:options]) if model[:options]
    input = {
      prompt: prompt_and_trigger,
      negative_prompt:,
      disable_safety_checker: true,
      width: dimension[0],
      height: dimension[1],
      aspect_ratio: params[:aspect_ratio],
      size: "#{dimension[0]}x#{dimension[1]}",
      apply_watermark: false,
      # seed: 9586464,
      refiner: 'expert_ensemble_refiner'
    }

    result = start_and_get_result(input, version, image_filename)
    data[:prediction] = result
  end

  data[:upscaled] =
    if model[:upscale] == false
      false
    else
      post_process_model = model[:disable_face_fixer] ? 'nightmareai/real-esrgan' : 'sczhou/codeformer'
      version = get_latest_model_version_id(post_process_model)
      image = result['output'].is_a?(Array) ? result['output'].first : result['output']
      input = {
        image:,
        upscale: 2,
        scale: 2
      }
      face_fix_result = start_and_get_result(input, version, image_filename)
      data[:face_fix_result] = face_fix_result['logs']
      true
    end
  basename = File.basename(image_filename)

  # Update metadata with the new image and prompt
  metadata[basename] = data
  save_metadata

  content_type :json
  erb :image, layout: false, locals: { basename:, prompt:, model: model[:model] }
end

# Serve the generated image
get '/image/:filename' do
  image_path = File.join(CACHE_DIR, params[:filename])
  if File.exist?(image_path)
    send_file(image_path, type: 'image/png', disposition: 'inline')
  else
    halt 404, 'Image not found'
  end
end

post '/upscale/:filename' do
  # upload the image to replicate
  image_path = File.join(CACHE_DIR, params[:filename])
  response = http
             .post('https://api.replicate.com/v1/files',
                   form: {
                     content: HTTP::FormData::File.new(image_path),
                     type: 'application/octet-stream',
                     filename: params[:filename],
                     upscale: 2
                   })

  puts response
  halt 500, "Failed to upload image: #{response.body}" unless response.status.success?

  image_url = JSON.parse(response.body)['urls']['get']

  # upscale the image
  model = 'cjwbw/real-esrgan'
  version = get_latest_model_version_id(model)
  input = {
    image: image_url
  }

  prompt = metadata.dig(params[:filename], 'prompt') || ''
  new_image_filename = File.join(CACHE_DIR, filename_for_prompt(prompt))

  start_and_get_result(input, version, new_image_filename)

  basename = File.basename(new_image_filename)

  erb :image, layout: false, locals: { basename:, prompt:, model: 'upscaled' }
end

post '/enhance_prompt' do
  prompt = JSON.parse(request.body.read)['prompt']

  ## forward the prompt to a llm (meta/meta-llama-3-8b) model and get the enhanced prompt
  model = 'meta/meta-llama-3-70b-instruct'
  version = get_latest_model_version_id(model)

  input = {
    prompt: <<~PROMPT,
      "Improve the following prompt so that it will deliver#{' '}
        astonishing results when used create an image with AI.
        Add desciptions, more context, and slightly more vivid language.
        Keep the prompt length between 3 and 5 sentences.
        Do not generate the image. Just create the new prompt.
        Be concise and use clear language. Do not be polite.
        Avoid "Here is the rewritten prompt:" or similar.
        -----
        #{prompt}.
    PROMPT
    top_k: 0,
    top_p: 0.9,
    max_tokens: 512,
    min_tokens: 30,
    temperature: 0.6,
    length_penalty: 1,
    prompt_template: '{prompt}',
    presence_penalty: 1.15,
    log_performance_metrics: false
  }

  prediction = forward_to_replicate(input, version)

  enhanced_prompt = poll_for_completion(prediction['id'])['output'].join('')
  # remove leading qutoes and white space until the first word
  enhanced_prompt = enhanced_prompt.sub(/^[^a-zA-Z]+/, '')
  # remove trailing qutoes and white space after the last word
  enhanced_prompt = enhanced_prompt.sub(/[^a-zA-Z]+$/, '')

  content_type :json
  { enhanced_prompt: }.to_json
end

# Route to delete an image and its metadata
delete '/image/:filename' do
  image_path = File.join(CACHE_DIR, params[:filename])

  if File.exist?(image_path)
    File.delete(image_path)
    metadata.delete(params[:filename])
    save_metadata
    status 200
  else
    halt 404, 'Image not found'
  end
end

# Route to get the list of images
get '/images' do
  @images = load_last_images(params[:filename])
  erb :images, layout: false
end

Sinatra::Application.run!(bind: '0.0.0.0')
__END__

@@image
<div class="i-c">
  <img src="/image/<%= basename %>" alt="<%= prompt&.gsub('"',"'",) %>" title="<%= prompt&.gsub('"',"'") %>" class="m-2">
  <div class="prompt">
    <p><%= prompt %></p>
  </div>
  <div class="controls">
    <button class="previous-btn btn btn-outline-warning" data-filename="<%= basename %>"><i class="fa fa-chevron-left"></i></button>
    <button class="delete-btn btn btn-outline-danger" data-filename="<%= basename %>"><i class="fa fa-trash-o"></i></button>
    <button class="load-prompt-btn btn btn-outline-info"><i class="fa fa-external-link"></i></button>
    <button class="upscale-btn btn btn-outline-primary" data-filename="<%= basename %>"><i class="fa fa-expand"></i></button>
    <button class="next-btn btn btn-outline-warning" data-filename="<%= basename %>"><i class="fa fa-chevron-right"></i></button>
    <div>
      <span class="dimensions">-</span>
      <span class="model"><%= model&.split('/')&.last %></span>
    </div>
    </div>
</div>

@@images
<% @images.each do |image| %>
  <%= erb :image, locals: { basename: image[:file], prompt: image[:prompt], model: image[:model] } %>
<% end %>

@@index
<!DOCTYPE html>
<html data-bs-theme="dark"  style="font-size:1.25rem">
<head>
  <title>Image Generator</title>
  <link rel="stylesheet" href="/application.css">
  <script src="/application.js"></script>

  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH" crossorigin="anonymous">
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-YvpcrYf0tY3lHB60NNkmXc5s9fDVZLESaAA55NDzOxhy9GkcIdslK1eN7N6jIeHz" crossorigin="anonymous"></script>  
 
  <link rel="stylesheet" href="/font-awesome/css/font-awesome.min.css">
</head>
<body>
  <form id="imageForm" action="/generate" method="post" class="row" style="max-width:98vw">
    <div class="col-md-9 p-4 align-center">

      <div class="input-group mb-2 mr-sm-2">
        <textarea id="prompt" name="prompt" cols="60", rows="5" class="form-control form-control-lg" tabindex="1" required><%= 
            @metadata.values.last['prompt'] || 'A beautiful landscape painting of a serene lake with mountains in the background.'
          %></textarea>
        <div class="input-group-append">
          <button id="enhancePrompt" tabindex="-1" class="btn btn-secondary btn-sm mt-2 mb-3">✨</button>
        </div>
      </div>

    </div>

    <div class="col-md-3 p-4">
      <div align="center">
        <button type="submit" tabindex="2"  class="btn btn-primary btn-md mb-2"><i class="fa fa-play"></i> Generate Image</button>
      </div>

      <div class="input-group mb-2 mr-sm-2">
        <div class="input-group-prepend">
          <div class="input-group-text">🚫</div>
        </div>
        <input id="negativePrompt" tabindex="-1" name="negative_prompt" class="form-control form-control-sm" value="ugly, deformed, noisy, blurry, distorted, cropped, worst quality, low quality, glitch, mutated, disfigured." />
      </div>
      
      <select name="model" class="form-control mb-2" tabindex="4">
        <% MODELS.each do |key, value| %>
          <option><%= key %></option>
        <% end %>
      </select>

      <div class="form-check-inline">
        <% aspect_ratios = ['16:9', '9:16', '1:1'] %>
        <% aspect_ratios.each do |aspect_ratio| %>
          <input class="form-check-input" type="radio" tabindex="5" name="aspect_ratio" id="aspect_ratio_<%= aspect_ratio %>" value="<%= aspect_ratio %>" <%= aspect_ratio == '16:9' ? 'checked' : '' %>>
          <label class="form-check-label" for="aspect_ratio_<%= aspect_ratio %>">
            <%= aspect_ratio %>
          </label>
          &nbsp;
        <% end %>
      </div>

      <!--
      <div style="display: inline-block; padding: 5px; text-align:center; vertical-align:center; padding: 10px; border: 1px solid white; border-radius: 5px; height: 75px; aspect-ratio: auto 16 / 9">16:9</div>
      <div style="display: inline-block;  padding: 5px; text-align:center; vertical-align:center; padding: 10px; border: 1px solid white; border-radius: 5px; height: 75px; aspect-ratio: auto 9 / 16">9:16</div>
      <div style="display: inline-block;  padding: 5px; text-align:center; vertical-align:center; padding: 10px; border: 1px solid white; border-radius: 5px; height: 75px; aspect-ratio: auto 1 / 1">1:1</div>
      -->

    </div>


  </form>
  
  <div id="result">
    <!-- The generated image will be displayed here -->
  </div>

  <br clear="all" />
  <div align="center">
    <button id="loadMore" class="btn btn-lg btn-secondary">Load More</button>
  </div>

</body>
</html>

