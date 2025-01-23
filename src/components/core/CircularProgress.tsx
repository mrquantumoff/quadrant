import { motion } from "motion/react";

const spinAnimation = { repeat: Infinity, duration: 15, ease: "linear" };

export default function CircularProgress() {
  return (
    <>
      <motion.div
        // ref={ref}
        initial={{ x: 100 }}
        animate={{
          x: 0,
        }}
        exit={{
          x: -100,
        }}
        whileHover={{ y: -5 }}
        transition={{ duration: 0.1, ease: "linear", type: "tween" }}
        className="hover:shadow-2xl rounded-full"
      >
        <div className="grid w-min h-min place-content-center">
          <motion.span
            animate={{ rotate: 3840 }}
            transition={spinAnimation}
            className={
              "  hover:drop-shadow-xs border-8 border-t-slate-700 border-slate-900 p-16 rounded-full font-extrabold "
            }
          />
        </div>
      </motion.div>
    </>
  );
}
