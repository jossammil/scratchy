// Open Peeps (Pablo Stanley, CC0) through DiceBear (MIT), bundled for R's V8.
import { createAvatar } from "@dicebear/core";
import * as openPeeps from "@dicebear/open-peeps";

globalThis.ExcPeeps = {
  svg: (options) => createAvatar(openPeeps, options || {}).toString(),
  options: () => JSON.stringify(openPeeps.schema.properties),
};
