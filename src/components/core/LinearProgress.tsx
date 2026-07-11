interface LinearProgressProps {
  progress: number;
  className?: string;
}

export default function LinearProgress({
  progress,
  className,
}: LinearProgressProps) {
  const percentage = Math.min(100, Math.max(0, progress));
  return (
    <>
      <div className={className + " bg-slate-700 rounded-full w-full "}>
        <div
          style={{ width: `${percentage}%` }}
          className={
            "text-xs font-medium text-slate-50 text-center p-0.5 leading-none rounded-full " +
            (percentage === 0 ? "bg-slate-800" : "bg-blue-600")
          }
        >
          {percentage}%
        </div>
      </div>
    </>
  );
}
