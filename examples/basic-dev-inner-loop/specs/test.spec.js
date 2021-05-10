
describe('The basic-dev-inner-loop example backend', () => {

  it('Responds on port 3000 through the service "node"', async () => {
    const res = await fetch('http://node:3000/');
    expect(res.status).toEqual(200);
  });

});
