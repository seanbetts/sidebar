export type ThingsBridgeInfo = {
  bridgeId: string;
  deviceId: string;
  deviceName: string;
  baseUrl: string;
  capabilities?: Record<string, boolean>;
  lastSeenAt: string | null;
  updatedAt: string | null;
};

export type ThingsBridgeStatus = {
  activeBridgeId: string | null;
  activeBridge: ThingsBridgeInfo | null;
  bridges: ThingsBridgeInfo[];
};
