export default function EnlightLogo({ size = 40, className = "" }) {
  return (
    <img
      src="/enlight-logo.png"
      alt="Enlight Lab"
      width={size}
      height={size}
      className={className}
      style={{ display: "block", objectFit: "contain" }}
    />
  );
}
