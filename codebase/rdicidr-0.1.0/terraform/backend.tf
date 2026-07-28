terraform {
  # The actual bucket, state key, and region are supplied
  # through the environment-specific backend files.
  backend "s3" {}
}