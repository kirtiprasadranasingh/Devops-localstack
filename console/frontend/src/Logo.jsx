export default function EnlightLogo({ className = "", variant = "default" }) {
  return (
    <span className={`el-logo ${variant === "run" ? "el-logo-run" : ""} ${className}`}>
      <span className="el-logo-icon-wrap">
        <img
          src="/enlight-logo.png"
          alt=""
          className="el-logo-img"
          width={36}
          height={36}
          aria-hidden="true"
        />
      </span>
      <span className="el-logo-text">Enlight Lab</span>
    </span>
  );
}
