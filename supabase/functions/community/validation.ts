import manifest from "./catalog.json" with { type: "json" };

type ObjectValue = Record<string, unknown>;
type Asset = {
  scenery: boolean;
  connectors: number;
  surface_mounted: boolean;
  release: boolean;
  collector: boolean;
  settings: Record<string, { kind: number; minimum: number; maximum: number }>;
  inputs: Record<string, boolean>;
  outputs: Record<string, boolean>;
};
const assets = Object.assign(Object.create(null), manifest.assets) as Record<
  string,
  Asset
>;
export const compatibility = manifest.compatibility;
export const MAX_BYTES = 5_000_000;
const safeId = (v: unknown): v is string =>
  typeof v === "string" && /^[A-Za-z0-9_-]{1,100}$/.test(v);
const object = (v: unknown): v is ObjectValue =>
  v !== null && typeof v === "object" && !Array.isArray(v);
const number = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v);
const integer = (v: unknown, min: number, max: number): v is number =>
  number(v) && Number.isInteger(v) && v >= min && v <= max;
const vector = (v: unknown, size: number): v is number[] =>
  Array.isArray(v) && v.length === size &&
  v.every((x) => number(x) && Math.abs(x) <= 1000);
function require(check: unknown, message: string): asserts check {
  if (!check) throw new Error(message);
}
function keys(value: ObjectValue, allowed: string[]) {
  require(
    Object.keys(value).every((k) => allowed.includes(k)),
    "Unsupported field",
  );
}
function limits(value: unknown, asset: Asset) {
  require(object(value), "Invalid setting limits");
  for (const [key, range] of Object.entries(value)) {
    const setting = Object.hasOwn(asset.settings, key)
      ? asset.settings[key]
      : undefined;
    require(
      setting && setting.kind === 0 && vector(range, 2) &&
        range[0] <= range[1] && range[0] >= setting.minimum &&
        range[1] <= setting.maximum,
      "Invalid setting limits",
    );
  }
}
function records(value: unknown): Map<string, ObjectValue> {
  require(
    Array.isArray(value) && value.length > 0 && value.length <= 5000,
    "Invalid construction list",
  );
  const result = new Map<string, ObjectValue>();
  for (const item of value) {
    require(object(item), "Invalid construction record");
    keys(item, ["uid", "piece", "position", "rotation", "config"]);
    require(
      safeId(item.uid) && !result.has(item.uid) &&
        typeof item.piece === "string",
      "Invalid piece identity",
    );
    const asset = assets[item.piece];
    require(
      asset && !asset.scenery && vector(item.position, 3) &&
        integer(item.rotation, 0, 3),
      "Invalid piece placement",
    );
    const config = item.config ?? {};
    require(object(config), "Invalid configuration");
    for (const [key, value] of Object.entries(config)) {
      if (key === "links") continue;
      if (key === "mount_target") {
        require(
          asset.surface_mounted && safeId(value),
          "Invalid mounting target",
        );
        continue;
      }
      if (key === "mount_basis") {
        require(
          asset.surface_mounted && mountingBasis(value),
          "Invalid mounting orientation",
        );
        continue;
      }
      const setting = Object.hasOwn(asset.settings, key)
        ? asset.settings[key]
        : undefined;
      require(setting, "Unknown mechanism setting");
      if (setting.kind === 0) {
        require(
          number(value) && value >= setting.minimum && value <= setting.maximum,
          "Setting outside supported range",
        );
      }
      if (setting.kind === 1) {
        require(typeof value === "boolean", "Invalid flag");
      }
      if (setting.kind === 2) {
        require(
          typeof value === "string" && value.length <= 200,
          "Invalid setting text",
        );
      }
    }
    result.set(item.uid, item);
  }
  for (const item of result.values()) {
    const config = (item.config ?? {}) as ObjectValue;
    const links = config.links ?? [];
    require(
      Array.isArray(links) && links.length <= 100,
      "Too many mechanism links",
    );
    const sender = assets[item.piece as string];
    if (sender.surface_mounted) {
      require(
        safeId(config.mount_target) && mountingBasis(config.mount_basis),
        "Missing mounting metadata",
      );
      const support = result.get(config.mount_target);
      require(
        support && support !== item &&
          !assets[support.piece as string].surface_mounted,
        "Missing or invalid mounting surface",
      );
    }
    for (const link of links) {
      require(object(link), "Invalid link");
      keys(link, ["event", "target", "action"]);
      require(
        typeof link.target === "string" && typeof link.event === "string" &&
          typeof link.action === "string",
        "Invalid link",
      );
      const target = result.get(link.target);
      require(target, "Missing link target");
      const receiver = assets[target.piece as string];
      require(
        Object.hasOwn(sender.outputs, link.event) &&
          Object.hasOwn(receiver.inputs, link.action) &&
          sender.outputs[link.event] === receiver.inputs[link.action],
        "Incompatible mechanism link",
      );
    }
  }
  return result;
}

function mountingBasis(value: unknown): value is number[] {
  if (!vector(value, 9)) return false;
  const dot = (a: number, b: number) =>
    value[a] * value[b] + value[a + 1] * value[b + 1] +
    value[a + 2] * value[b + 2];
  for (const a of [0, 3, 6]) {
    if (Math.abs(dot(a, a) - 1) > 0.00001) return false;
    for (const b of [0, 3, 6]) {
      if (a !== b && Math.abs(dot(a, b)) > 0.00001) return false;
    }
  }
  const determinant = value[0] * (value[4] * value[8] - value[5] * value[7]) -
    value[3] * (value[1] * value[8] - value[2] * value[7]) +
    value[6] * (value[1] * value[5] - value[2] * value[4]);
  return Math.abs(determinant - 1) < 0.00001;
}

// Keep the legacy digest argument for API-v1 callers. Support is established by
// the schema, assets, settings and ports actually used below, not catalog equality.
export function validatePuzzle(value: unknown, _catalog?: unknown): ObjectValue {
  require(object(value), "Invalid puzzle");
  keys(value, [
    "id",
    "name",
    "description",
    "creator",
    "difficulty",
    "version",
    "revision",
    "pieces",
    "solution",
    "environment_instances",
    "permissions",
    "inventory",
    "configuration_limits",
    "bounds",
    "restricted_zones",
    "objectives",
    "hints",
    "guidance",
    "camera",
    "awards",
    "validation",
    "status",
    "required_assets",
    "time_limit",
    "modified",
  ]);
  require(
    safeId(value.id) && integer(value.version, 1, 3) &&
      integer(value.revision, 1, 100000),
    "Unsupported puzzle identity or version",
  );
  require(
    typeof value.name === "string" && value.name.trim().length > 0 &&
      value.name.length <= 80,
    "Invalid puzzle title",
  );
  for (
    const [key, max] of [["description", 2000], ["creator", 80], [
      "difficulty",
      80,
    ], ["modified", 80]] as const
  ) {
    require(
      value[key] === undefined ||
        (typeof value[key] === "string" &&
          (value[key] as string).length <= max),
      "Invalid text",
    );
  }
  require(value.status === "published", "Publish a tested puzzle first");
  const pieces = records(value.pieces), solution = records(value.solution);
  require(
    [...pieces.values()].some((p) => assets[p.piece as string].release),
    "Missing marble release",
  );
  require(
    vector(value.bounds, 6) && value.bounds[0] < value.bounds[2] &&
      value.bounds[1] < value.bounds[3] && value.bounds[4] < value.bounds[5],
    "Invalid bounds",
  );
  const scenery = value.environment_instances ?? [];
  require(Array.isArray(scenery) && scenery.length <= 5000, "Invalid scenery");
  const sceneryIds = new Set<string>();
  for (const item of scenery) {
    require(object(item), "Invalid scenery");
    keys(item, ["uid", "asset", "position", "rotation"]);
    require(
      safeId(item.uid) && !pieces.has(item.uid) && !solution.has(item.uid) &&
        !sceneryIds.has(item.uid) && typeof item.asset === "string" &&
        assets["environment:" + item.asset]?.scenery &&
        vector(item.position, 3) && integer(item.rotation, 0, 3),
      "Invalid scenery asset or placement",
    );
    sceneryIds.add(item.uid);
  }
  const inventory = value.inventory ?? {};
  require(
    object(inventory) && Object.keys(inventory).length <= 500,
    "Invalid inventory",
  );
  for (const [id, count] of Object.entries(inventory)) {
    require(
      assets[id] && !assets[id].scenery && integer(count, 0, 5000),
      "Invalid inventory piece",
    );
  }
  const restrictions = value.configuration_limits ?? {};
  require(object(restrictions), "Invalid configuration limits");
  for (const [id, range] of Object.entries(restrictions)) {
    require(assets[id] && !assets[id].scenery, "Unknown restricted piece");
    limits(range, assets[id]);
  }
  const permissions = value.permissions ?? {};
  require(object(permissions), "Invalid permissions");
  for (const [uid, permission] of Object.entries(permissions)) {
    require(pieces.has(uid) && object(permission), "Missing permitted piece");
    keys(permission, [
      "move",
      "rotate",
      "configure",
      "remove",
      "duplicate",
      "config_keys",
      "limits",
    ]);
    const asset = assets[pieces.get(uid)!.piece as string];
    for (const key of ["move", "rotate", "configure", "remove", "duplicate"]) {
      require(
        permission[key] === undefined || typeof permission[key] === "boolean",
        "Invalid permission flag",
      );
    }
    require(
      permission.config_keys === undefined ||
        (Array.isArray(permission.config_keys) &&
          permission.config_keys.every((k) =>
            typeof k === "string" && Object.hasOwn(asset.settings, k)
          )),
      "Invalid permitted setting",
    );
    limits(permission.limits ?? {}, asset);
  }
  const objectives = value.objectives;
  require(
    Array.isArray(objectives) && objectives.length > 0 &&
      objectives.length <= 100,
    "Invalid objectives",
  );
  for (const goal of objectives) {
    require(object(goal), "Invalid objective");
    keys(goal, ["type", "target", "count", "source", "event", "time_limit"]);
    require(
      typeof goal.target === "string" && pieces.has(goal.target) &&
        ["deliver", "activate"].includes(goal.type as string),
      "Invalid objective target",
    );
    const asset = assets[pieces.get(goal.target)!.piece as string];
    if (goal.type === "deliver") {
      require(
        asset.collector && integer(goal.count ?? 1, 1, 5000),
        "Invalid delivery objective",
      );
    }
    if (goal.type === "activate") {
      require(
        typeof goal.event === "string" &&
          Object.hasOwn(asset.outputs, goal.event),
        "Invalid activation objective",
      );
    }
    require(
      goal.source === undefined || goal.source === "" ||
        (typeof goal.source === "string" && pieces.has(goal.source) &&
          assets[pieces.get(goal.source)!.piece as string].release),
      "Invalid marble source",
    );
    require(
      goal.time_limit === undefined ||
        (number(goal.time_limit) && goal.time_limit >= 0 &&
          goal.time_limit <= 3600),
      "Invalid objective time limit",
    );
  }
  require(
    value.time_limit === undefined ||
      (number(value.time_limit) && value.time_limit >= 0 &&
        value.time_limit <= 3600),
    "Invalid time limit",
  );
  const zones = value.restricted_zones ?? [];
  require(
    Array.isArray(zones) && zones.length <= 100 &&
      zones.every((z) => vector(z, 6) && z.slice(3).every((n) => n > 0)),
    "Invalid restricted zone",
  );
  const hints = value.hints ?? [];
  require(
    Array.isArray(hints) && hints.length <= 20 &&
      hints.every((h) => typeof h === "string" && h.length <= 500),
    "Invalid hints",
  );
  const guidance = value.guidance === undefined ? [] : value.guidance;
  require(Array.isArray(guidance) && guidance.length <= 32, "Invalid guidance");
  require(value.guidance === undefined || value.version === 3, "Guidance requires format 3");
  for (const step of guidance) {
    require(object(step), "Invalid guidance step");
    keys(step, ["kind", "target", "connector", "position", "text", "appear", "complete"]);
    require(["attention", "target", "direction", "interaction", "problem"].includes(step.kind as string) &&
      ["build", "run", "always"].includes(step.appear as string) &&
      ["selected", "connected", "run_started", "objective", "dismissed"].includes(step.complete as string), "Invalid guidance condition");
    require((step.text === undefined || (typeof step.text === "string" && step.text.length <= 200)) &&
      (step.position === undefined || vector(step.position, 3)) &&
      integer(step.connector === undefined ? -1 : step.connector, -1, 100), "Invalid guidance presentation");
    const uid = step.target === undefined ? "" : step.target;
    require(typeof uid === "string" && (uid === "" || pieces.has(uid)), "Missing guidance target");
    require(uid !== "" || (!(["selected", "connected", "objective"].includes(step.complete as string)) && (step.connector ?? -1) === -1), "Guidance needs a target");
    if (step.complete === "connected") require(integer(step.connector, 0, 100), "Guidance needs a connector");
    if (step.complete === "objective") require(objectives.some((goal) => goal.target === uid), "Missing guidance objective");
    if (uid !== "" && (step.connector as number) >= 0) {
      const asset = assets[pieces.get(uid)!.piece as string];
      require((step.connector as number) < (asset.connectors ?? 0), "Missing guidance connector");
    }
  }
  const required = value.required_assets ?? [];
  require(
    Array.isArray(required) && required.length <= 500 &&
      required.every((id) =>
        typeof id === "string" && Object.hasOwn(assets, id)
      ),
    "Invalid required asset",
  );
  const camera = value.camera ?? {};
  require(object(camera), "Invalid camera");
  keys(camera, ["focus", "yaw", "pitch", "distance"]);
  if (Object.keys(camera).length) {
    require(
      vector(camera.focus, 3) && number(camera.yaw) &&
        Math.abs(camera.yaw) <= 1000 && number(camera.pitch) &&
        Math.abs(camera.pitch) <= Math.PI && number(camera.distance) &&
        camera.distance >= 1 && camera.distance <= 1000,
      "Invalid camera",
    );
  }
  const awards = value.awards ?? {};
  require(object(awards), "Invalid awards");
  keys(awards, ["time", "pieces"]);
  for (const n of Object.values(awards)) {
    require(number(n) && n >= 0 && n <= 100000, "Invalid award");
  }
  require(object(value.validation), "Missing test record");
  keys(value.validation, [
    "physics_success",
    "fingerprint",
    "seconds",
    "engine",
    "tested_at",
  ]);
  require(
    value.validation.physics_success === true &&
      typeof value.validation.fingerprint === "string" &&
      /^[a-f0-9]{64}$/.test(value.validation.fingerprint),
    "Missing successful player test",
  );
  for (const key of ["engine", "tested_at"]) {
    require(
      value.validation[key] === undefined ||
        (typeof value.validation[key] === "string" &&
          (value.validation[key] as string).length <= 100),
      "Invalid test record",
    );
  }
  require(
    value.validation.seconds === undefined ||
      (number(value.validation.seconds) && value.validation.seconds >= 0 &&
        value.validation.seconds <= 3600),
    "Invalid test time",
  );
  // Structural safety only. The game validates player permissions/collisions and
  // the author must run Test as Player; the server does not claim solvability.
  return value;
}
