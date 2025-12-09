exports.handler = function (context, event, callback) {
  const twiml = new Twilio.twiml.VoiceResponse();

  const gather = twiml.gather({
    input: 'speech',
    speechTimeout: 'auto',
    action: '/capture-order',
    method: 'POST'
  });
  gather.say(
    'Hi! You have reached the Ordering Intelligence test line. '
    + 'Please describe your order after the tone and our assistant will transcribe your message.'
  );

  twiml.say('We did not receive any speech input. Goodbye.');
  callback(null, twiml);
};
