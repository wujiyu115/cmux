// Deliberately missing a manifest: the loader must reject it.
export default { createConnector: () => ({ id: "bad" }) };
