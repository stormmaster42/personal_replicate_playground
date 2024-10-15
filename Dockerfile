# Use the official Ruby image from the Docker Hub
FROM ruby:3.1

# Set the working directory in the container
WORKDIR /app

# Copy the Ruby script and Gemfile into the container
COPY . /app/

# Install dependencies
RUN gem install bundler 

# Expose the port that the Sinatra app will run on
EXPOSE 8080

# Command to run the Sinatra app
CMD ["ruby", "gen.rb"]
