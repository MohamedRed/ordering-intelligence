exports.handler = function (context, event, callback) {
  const twiml = new Twilio.twiml.VoiceResponse();
  if (event.SpeechResult) {
    console.log('Captured order:', event.SpeechResult);
    twiml.say('Thanks! We captured your order as: ' + event.SpeechResult);
  } else {
    twiml.say('Thanks! We did not receive any audio but will transfer you to a team member.');
  }
  twiml.hangup();
  callback(null, twiml);
};
