/** @format */

import { motion } from "motion/react";

export interface IButtonProps {
  onClick: () => void;
  className?: string;
  children?: React.ReactNode;
  fullRound?: boolean;
  animate?: boolean;
}
export default function Button({
  onClick,
  children,
  className,
  fullRound,
  animate,
}: IButtonProps) {
  const fullRoundClass = fullRound ? "rounded-full" : "rounded-4xl";
  return (
    <motion.button
      onClick={onClick}
      whileHover={animate ? { y: -5, scale: 1.1 } : {}}
      whileTap={{ scale: 0.9 }}
      transition={{ duration: 0.15 }}
      className={
        fullRoundClass +
        " p-2 font-extrabold hover:cursor-pointer  " +
        className +
        " "
      }
    >
      {children}
    </motion.button>
  );
}
