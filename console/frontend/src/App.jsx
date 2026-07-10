import { useCallback, useEffect, useState } from "react";
import Home from "./Home";
import PipelineRun from "./PipelineRun";

function getRunId() {
  return new URLSearchParams(window.location.search).get("id");
}

function isRunPage() {
  return window.location.pathname === "/run" || window.location.pathname.startsWith("/run/");
}

export default function App() {
  const [page, setPage] = useState(isRunPage() ? "run" : "home");
  const [runId, setRunId] = useState(getRunId());
  const [appUrl, setAppUrl] = useState("");

  useEffect(() => {
    fetch("/api/status")
      .then((r) => r.json())
      .then((d) => setAppUrl(d.demo?.app_url || d.links?.application || ""))
      .catch(() => {});
  }, []);

  const goRun = useCallback(() => {
    window.history.pushState({}, "", "/run");
    setRunId(null);
    setPage("run");
  }, []);

  const goHome = useCallback(() => {
    window.history.pushState({}, "", "/");
    setRunId(null);
    setPage("home");
  }, []);

  useEffect(() => {
    function onPop() {
      if (isRunPage()) {
        setPage("run");
        setRunId(getRunId());
      } else {
        setPage("home");
        setRunId(null);
      }
    }
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  if (page === "run") {
    return <PipelineRun executionId={runId} onBack={goHome} appUrl={appUrl} />;
  }
  return <Home onRunDemo={goRun} />;
}
