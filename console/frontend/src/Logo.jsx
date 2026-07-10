export default function EnlightLogo({ className = "" }) {
  return (
    <span className={`el-logo ${className}`}>
      <span className="el-logo-mark" aria-hidden="true">
        {"{·}"}
      </span>
      <span className="el-logo-text">Enlight Lab</span>
    </span>
  );
}
