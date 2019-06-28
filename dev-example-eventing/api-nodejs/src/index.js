const Cloudevent = require("cloudevents-sdk");

const results = require('./results-from-processing');

const express = require("express");
const app = express();
const port = 8080;
app.get('/', (req, res) => {
  res.status(200).send('Ok');
});
app.listen(port, () => console.log(`Example app listening on port ${port}!`));

const config = {
  method: "POST",
  url   : "http://kafka001-broker"
};

const contentType = "application/cloudevents+json; charset=utf-8";
const startTime   = new Date();
const schemaurl   = "http://cloudevents.io/schema.json";

const workerStartEvent = new Cloudevent(Cloudevent.specs["0.2"])
  .type("dev.ystack.example.start")
  .source("urn:event:from:example-api/resource/123")
  .contenttype(contentType)
  .time(startTime)
  .schemaurl(schemaurl)
  .data({"workerStatus":"running"})
  .addExtension("ystack-ext","sample value")
  ;

const binding = new Cloudevent.bindings["http-binary0.2"](config);

binding.emit(workerStartEvent)
  .then(response => {
    console.log('Response from event emit', JSON.stringify(response));
  }).catch(err => {
    console.error('Error from event emit', err);
    process.exit(1);
  });
