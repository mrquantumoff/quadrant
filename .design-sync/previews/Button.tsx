// Authored preview for Quadrant's Button. Each export = one card cell.
import { Button } from "quadrant-next";
import { FaDownload, FaPlus, FaTrash } from "react-icons/fa6";

const noop = () => {};

export function Primary() {
  return (
    <div className="p-6 bg-slate-900">
      <Button className="bg-blue-600 hover:bg-blue-700 text-slate-50" onClick={noop}>
        Sign in via OAuth
      </Button>
    </div>
  );
}

export function Variants() {
  return (
    <div className="p-6 bg-slate-900 flex flex-wrap gap-3 items-center">
      <Button className="bg-blue-600 hover:bg-blue-700 text-slate-50" onClick={noop}>
        Primary
      </Button>
      <Button className="bg-emerald-600 hover:bg-emerald-700 text-slate-50" onClick={noop}>
        <span className="flex items-center gap-2">
          <FaPlus /> Create a new modpack
        </span>
      </Button>
      <Button className="bg-slate-800 hover:bg-slate-700 text-slate-50" onClick={noop}>
        Neutral
      </Button>
      <Button className="bg-slate-800 hover:bg-red-700 text-slate-50" onClick={noop}>
        <span className="flex items-center gap-2">
          <FaTrash /> Delete your usage data
        </span>
      </Button>
    </div>
  );
}

export function IconRound() {
  return (
    <div className="p-6 bg-slate-900 flex gap-3 items-center">
      <Button fullRound className="bg-blue-600 hover:bg-blue-700 text-slate-50 px-3" onClick={noop}>
        <FaDownload />
      </Button>
      <Button fullRound animate className="bg-emerald-600 hover:bg-emerald-700 text-slate-50 px-3" onClick={noop}>
        <FaPlus />
      </Button>
    </div>
  );
}
