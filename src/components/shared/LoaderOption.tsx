/** @format */

import { ModLoader } from "../../intefaces";
import {
  getModLoaderOptions,
  ModLoaderProvider,
} from "../../modLoaders";

export interface ILoaderOptionsProps {
  loader: ModLoader | string;
  providers?: ModLoaderProvider[];
}

export default function LoaderOptions({
  loader,
  providers,
}: ILoaderOptionsProps) {
  return (
    <>
      <option
        value={ModLoader.Unknown}
        defaultChecked={ModLoader.Unknown === loader}
        className="rounded-2xl font-semibold"
        key={ModLoader.Unknown}
      >
        -
      </option>
      {getModLoaderOptions(providers).map((option) => (
        <option
          value={option.value}
          defaultChecked={option.value === loader}
          className="rounded-2xl font-semibold"
          key={option.value}
        >
          {option.label}
        </option>
      ))}
    </>
  );
}
