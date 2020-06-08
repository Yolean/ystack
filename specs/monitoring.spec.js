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

  });

});
