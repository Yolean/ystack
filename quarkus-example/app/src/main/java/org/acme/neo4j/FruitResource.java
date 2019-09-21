package org.acme.neo4j;

import java.util.concurrent.CompletionStage;

import javax.inject.Inject;
import javax.ws.rs.Consumes;
import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import javax.ws.rs.core.Response.ResponseBuilder;

import org.neo4j.driver.Driver;
import org.neo4j.driver.async.AsyncSession;

@Path("fruits")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class FruitResource {

  @Inject
  Driver driver;

  @GET
  public CompletionStage<Response> get() {
    AsyncSession session = driver.asyncSession();
    return session
      .runAsync("MATCH (f:Fruit) RETURN f ORDER BY f.name")
      .thenCompose(cursor ->
        cursor.listAsync(record -> Fruit.from(record.get("f").asNode()))
      )
      .thenCompose(fruits ->
        session.closeAsync().thenApply(signal -> fruits)
      )
      .thenApply(Response::ok)
      .thenApply(ResponseBuilder::build);
  }

}
