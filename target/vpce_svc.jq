[
  .Subnets[] | {
    "name": .Tags[] | select(.Key == "Name") | .Value,
    "id": .SubnetId
  }
] | {
  "module": [
    .[] | .id as $id | {
      "key": "\(.name)_\(.id)",
      "value": {
        "source": "./vpce_svc",
        "scanner_account_id": "${var.scanner_account_id}",
        "subnet_ids": ["\($id)"]
      }
    }
  ] | from_entries,
  "locals": {
    "vpce_svc_ids": map("${module.\(.name)_\(.id).vpce-service.id}")
  }
}
