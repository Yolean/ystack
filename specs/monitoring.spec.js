describe("Monitoring", () => {

  describe("Ystack's proxy", () => {

    it("Has Prometheus on port 9090", async () => {
      const prom = await fetch('http://monitoring.ystack:9090/api/v1/status/runtimeinfo').then(res => res.json());
      expect(prom).toHaveProperty('data.reloadConfigSuccess', true);
    });

    it("Has Alertmanager on port 9093", async () => {
      const alerts = await fetch('http://monitoring.ystack:9093/api/v2/alerts').then(res => res.json());
      expect(alerts).toBeInstanceOf(Array);
    });

    it("Prometheus has the kubernetes-assert PodMonitor", async () => {
      const config = await fetch('http://monitoring.ystack:9090/api/v1/status/config').then(res => res.json());
      expect(config).toHaveProperty('data.yaml');
      expect(config.data.yaml).toMatch(/job_name: monitoring\/kubernetes-assert\/0/);
    });

    it("Prometheus finds at lest one target (this one) for the PodMonitor", async () => {
      const targets = await fetch('http://monitoring.ystack:9090/api/v1/targets?state=active').then(res => res.json());
      expect(targets).toHaveProperty('data.activeTargets');
      expect(targets.data.activeTargets).toEqual(
        expect.arrayContaining([
          expect.objectContaining({scrapePool: 'monitoring/kubernetes-assert/0'})
        ])
      );
    });

  });

});
