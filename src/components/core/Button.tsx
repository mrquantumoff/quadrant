export interface IButtonProps {
  onClick: () => void;
  className?: string;
  children?: React.ReactNode;
  fullRound?: boolean;
}
export default function Button({
  onClick,
  children,
  className,
  fullRound,
}: IButtonProps) {
  const fullRoundClass = fullRound ? "rounded-full" : "rounded-2xl";
  return (
    <button
      onClick={onClick}
      className={
        fullRoundClass +
        " p-2 font-extrabold hover:cursor-pointer  " +
        className +
        " "
      }
    >
      {children}
    </button>
  );
}
