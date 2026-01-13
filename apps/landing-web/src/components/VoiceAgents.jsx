const VoiceAgents = () => (
  <section className="voice">
    <div className="container voice-grid">
      <div className="voice-copy">
        <span className="eyebrow">Voice Agents</span>
        <h2>Design agents that sound like your best team member.</h2>
        <p>
          Create personalities, enforce policies, and keep every call aligned
          with your brand voice.
        </p>
        <div className="pill-row">
          <span>Brand tone</span>
          <span>Menu logic</span>
          <span>Escalations</span>
          <span>Analytics</span>
        </div>
      </div>
      <div className="voice-panel">
        <div className="voice-panel-card">
          <h3>Live call summary</h3>
          <p>Orders, modifiers, and upsells captured in real time.</p>
          <div className="voice-panel-metrics">
            <div>
              <strong>+18%</strong>
              <span>upsell lift</span>
            </div>
            <div>
              <strong>32s</strong>
              <span>avg hold</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);

export default VoiceAgents;
