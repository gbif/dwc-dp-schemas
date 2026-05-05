# dwc-dp-schemas

Maven artifact packaging the [DwC-DP](https://github.com/gbif/dwc-dp) JSON schema definitions
for classpath access in Java projects.

## Dependency

```xml
<dependency>
  <groupId>org.gbif</groupId>
  <artifactId>dwc-dp-schemas</artifactId>
  <version>0.0.1</version>
</dependency>
```

## Classpath layout

```
schemas/
  {version}/
    dwc-dp-profile.json     — top-level DwC-DP profile descriptor
    index.json              — index of all tables in this version
    version.json            — version metadata
    table-schemas/
      agent.json
      event.json
      occurrence.json
      ... (one file per DwC-DP table)
```

## Loading schemas in Java

```java
// Profile
InputStream profile = getClass().getResourceAsStream("/schemas/0.1/dwc-dp-profile.json");

// Index
InputStream index = getClass().getResourceAsStream("/schemas/0.1/index.json");

// Table schema
InputStream eventSchema = getClass().getResourceAsStream("/schemas/0.1/table-schemas/event.json");
```

## Versioning

The schema version (`0.1`, `0.2`, …) corresponds to the DwC-DP spec version tracked in
[gbif/dwc-dp](https://github.com/gbif/dwc-dp). Multiple versions can coexist in the same jar
under separate paths, allowing consumers to validate against a specific spec version.

The Maven artifact version (`0.0.1`, `0.0.2`, …) tracks packaging changes independently of the
schema version — e.g. adding a new spec version to an existing jar bumps the artifact version
without changing the schema paths.