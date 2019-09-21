package org.acme.neo4j;

import org.neo4j.driver.types.Node;

public class Fruit {

  public static Fruit from(Node node) {
    return new Fruit(node.id(), node.get("name").asString());
  }

  public Long id;

  public String name;

  public Fruit() {
    // This is needed for the REST-Easy JSON Binding
  }

  public Fruit(String name) {
    this.name = name;
  }

  public Fruit(Long id, String name) {
    this.id = id;
    this.name = name;
  }

}
