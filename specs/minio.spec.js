describe("Ystack minio", () => {
  
  describe("http", () => {
    
    it("The blobs-minio service (a legacy name) uses port 80", async () => {
      const blobs = await fetch('http://blobs-minio.ystack/').then(res => res.text());
      expect(blobs).toMatch(/AccessDenied/);  
    });
    
  });

});
