interface LinearProgressProps {
  progress: number;
  className?: string;
}

export default function LinearProgress({
  progress,
  className,
}: LinearProgressProps) {
  const percentage = progress;
  return (
    <>
      <div
        className={
          className + " bg-slate-200 rounded-full dark:bg-slate-700 w-full "
        }
      >
        <div
          className={
            " w-[" +
            percentage +
            "%]  text-xs font-medium text-sky-100 text-center p-0.5 leading-none rounded-full " +
            (percentage === 0 ? "bg-slate-800" : "bg-blue-800")
          }
        >
          {percentage}%
        </div>
      </div>
    </>
  );
}
