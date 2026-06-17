import "dotenv/config";

import { loadConfig } from "@ordering-intelligence/config";
import { createChannelCommsApp } from "./app";
import { ChannelCommsConfig } from "./config";

const config = loadConfig("channel-comms") as unknown as ChannelCommsConfig;

const port = Number(process.env.PORT || config.PORT || 8091);

const app = createChannelCommsApp(config);

app.listen(port, () => {
  console.log(`channel-comms listening on ${port}`);
});
