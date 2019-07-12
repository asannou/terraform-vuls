all: vpce_svc.tf.json

vpce_svc_subnet_ids.txt: vpce_svc_subnet_ids.jq
	aws ec2 describe-instances --filters 'Name=tag:Vuls,Values=1' | jq -r -f $(word 1, $+) > $@

vpce_svc_subnets.json: vpce_svc_subnet_ids.txt vpce_svc_subnets.jq
	cat $(word 1, $+) | xargs aws ec2 describe-subnets --subnet-ids | jq -f $(word 2, $+) > $@

vpce_svc.tf.json: vpce_svc_subnets.json vpce_svc_tf.jq
	cat $(word 1, $+) | jq -f $(word 2, $+) > $@

clean:
	rm -f *.tf.json

.INTERMEDIATE: vpce_svc_subnet_ids.txt

.SECONDARY: vpce_svc_subnets.json

.PHONY: all clean
