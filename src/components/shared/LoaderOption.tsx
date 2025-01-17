import { ModLoader } from "../../intefaces";

export interface ILoaderOptionsProps {
  loader: ModLoader | string;
}

export default function LoaderOptions({ loader }: ILoaderOptionsProps) {
  return (
    <>
      <option
        value={ModLoader.Forge}
        // defaultChecked={ModLoader.Forge == loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.Forge}
      >
        Forge
      </option>
      <option
        value={ModLoader.Fabric}
        defaultChecked={ModLoader.Fabric == loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.Fabric}
      >
        Fabric
      </option>
      <option
        value={ModLoader.NeoForge}
        defaultChecked={ModLoader.NeoForge == loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.NeoForge}
      >
        NeoForge
      </option>
      <option
        value={ModLoader.Quilt}
        defaultChecked={ModLoader.Quilt == loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.Quilt}
      >
        Quilt
      </option>
      <option
        value={ModLoader.Rift}
        defaultChecked={ModLoader.Rift == loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.Rift}
      >
        Rift
      </option>
    </>
  );
}
