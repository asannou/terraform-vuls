all: vpce_svc.tf.json

vpce_svc.tf.json:
	aws ec2 describe-instances --filters 'Name=tag:Vuls,Values=1' | jq -r '[.Reservations[].Instances[].SubnetId] | unique | .[] | select(. != null)' | xargs aws ec2 describe-subnets --subnet-ids | jq -f vpce_svc.jq > $@

.PHONY: all vpce_svc.tf.json
