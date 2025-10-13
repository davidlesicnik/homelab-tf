# Allow reading secret data
path "secret/data/*" {
  capabilities = ["read"]
}

# Allow listing and reading metadata
path "secret/metadata/*" {
  capabilities = ["list", "read"]
}