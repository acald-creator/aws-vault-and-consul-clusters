acl = {
    enable = true
    default_policy = "deny"
    enable_token_persistence = true
}

node_prefix "" {
    policy = "read"
}

service_prefix "" {
    policy = read
}

query_prefix "" {
    policy = "read"
}