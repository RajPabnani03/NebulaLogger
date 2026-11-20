---
layout: default
---

## LogBatchPurgeScheduler class

Schedulable class used to schedule the batch job `LogBatchPurger`

### Related

[LogBatchPurger](LogBatchPurger)

---

### Constructors

#### `LogBatchPurgeScheduler()`

Default constructor. Uses `LogBatchPurger.getDefaultBatchSize()`, controlled by the custom metadata record `LoggerParameter.LogBatchPurgerDefaultBatchSize`, or `500` as the default.

#### `LogBatchPurgeScheduler(Integer batchSize)`

Construct that accepts the batch size as a parameter.

##### Parameters

| Param       | Description                                                                   |
| ----------- | ----------------------------------------------------------------------------- |
| `batchSize` | - The size of the records per batch job / instance. Max is 5000. Minium is 1. |

---

### Methods

#### `execute(System.SchedulableContext schedulableContext)` → `void`

Required by the Database.Schedulable interface, this method kicks off the LogBatchPurger batch class on a scheduled basis.

##### Parameters

| Param                | Description                                                                     |
| -------------------- | ------------------------------------------------------------------------------- |
| `schedulableContext` | The instance of `System.SchedulableContext` provided by the platform at runtime |

---
