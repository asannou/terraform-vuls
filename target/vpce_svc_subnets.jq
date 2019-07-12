[
  .Subnets[] | {
    "name": .Tags[] | select(.Key == "Name") | .Value,
    "id": .SubnetId
  }
]
