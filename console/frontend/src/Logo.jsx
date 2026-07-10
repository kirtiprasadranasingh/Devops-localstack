export default function EnlightLogo({ className = "" }) {
  return (
    <span className={`el-logo ${className}`}>
      <img
        src="/enlight-logo.png"
        alt=""
        className="el-logo-img"
        width={36}
        height={36}
        aria-hidden="true"
      />
      <span className="el-logo-text">Enlight Lab</span>
    </span>
  );
}
