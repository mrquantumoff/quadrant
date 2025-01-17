interface LinearProgressProps {
  progress: number;
  className?: string;
}

export default function LinearProgress({
  progress,
  className,
}: LinearProgressProps) {
  const percentage = Math.round(progress * 100);
  return (
    <>
      <div
        className={
          className + " w-full bg-slate-200 rounded-full dark:bg-slate-700"
        }
      >
        <div
          className={
            " w-[" +
            percentage +
            "%] bg-sky-600 text-xs font-medium text-sky-100 text-center p-0.5 leading-none rounded-full"
          }
        >
          {percentage}%
        </div>
      </div>
    </>
  );
}
