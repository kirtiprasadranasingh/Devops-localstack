export default function EnlightLogo({ className = "", variant = "default", size = "default" }) {
  const imgSize = size === "lg" ? 48 : 44;
  return (
    <span
      className={`el-logo ${variant === "run" ? "el-logo-run" : ""} ${size === "lg" ? "el-logo-lg" : ""} ${className}`}
    >
      <img
        src="/enlight-logo.png"
        alt=""
        className="el-logo-img"
        width={imgSize}
        height={imgSize}
        aria-hidden="true"
      />
      <span className="el-logo-text">Enlight Lab</span>
    </span>
  );
}
