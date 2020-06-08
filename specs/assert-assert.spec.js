// This is quite imporant to keep up-to-date while we're getting used to non-interactive Jest watch
const ASSERT_FILES_MIN = 3;

describe("Ystack specs validity", () => {

  it(`Has seen at least ${ASSERT_FILES_MIN} spec files`, async () => {
    expect(await promValue(`assert_files_seen{pod="${process.env.POD_NAME}"}`))
      .toBeGreaterThanOrEqual(ASSERT_FILES_MIN);
  });
  
});
