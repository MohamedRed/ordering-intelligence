import { channels } from '../data/channels';

const ChannelRow = () => (
  <section className="channels">
    <div className="container">
      <p className="channels-title">Liive connects every ordering channel.</p>
      <div className="channels-row">
        {channels.map((channel) => (
          <span className="channel-pill" key={channel}>
            {channel}
          </span>
        ))}
      </div>
    </div>
  </section>
);

export default ChannelRow;
