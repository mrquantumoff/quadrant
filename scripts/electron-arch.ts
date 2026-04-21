export type ElectronArch = "x64" | "arm64";

export function normalizeElectronArch(arch: string | undefined): ElectronArch {
  const normalized = (arch ?? process.arch).trim().toLowerCase();

  switch (normalized) {
    case "x64":
    case "amd64":
    case "x86_64":
      return "x64";
    case "arm64":
    case "aarch64":
    case "arm":
      return "arm64";
    default:
      throw new Error(
        `Unsupported Electron architecture "${arch}". Expected one of x64, x86_64, amd64, arm64, aarch64, or arm.`,
      );
  }
}
