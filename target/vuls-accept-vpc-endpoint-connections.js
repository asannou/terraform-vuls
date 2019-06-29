#!/usr/bin/env node
'use strict';

const SERVICE_IDS = process.env.SERVICE_IDS.split(' ');

const AWS = require('aws-sdk');
const ec2 = new AWS.EC2();

exports.handler = (event, context, callback) => {
  const id = event.serviceId;
  const endpointIds = event.vpcEndpointIds;
  if (SERVICE_IDS.includes(id)) {
    const params = {
      ServiceId: id,
      VpcEndpointIds: endpointIds
    };
    ec2.acceptVpcEndpointConnections(params, callback);
  } else {
    const err = new Error(`${id} does not accept`);
    callback(err, null);
  }
};

if (require.main === module) {
  const argv = process.argv.slice(2);
  exports.handler({
    serviceId: argv.shift(),
    vpcEndpointIds: argv,
  }, undefined, (err, data) => {
    console.log(err, data);
  });
}

