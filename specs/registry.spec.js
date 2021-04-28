describe("Builds registry", () => {
      
  it("Registry is up, with storage", async () => {
    const v2 = await fetch('http://builds-registry.ystack/v2/').then(res => res.json());
    expect(v2).toEqual({});
  });
  
});
 