
# HelloID-Conn-Prov-Source-Zermelo
| :warning: Warning |
|:---------------------------|
| Note that this connector is "a work in progress" and therefore not ready for use in your production environment.

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-Zermelo](#HelloID-Conn-Prov-Source-Zermelo)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [Endpoints](#endpoints)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
      - [Logic in-depth](#logic-in-depth)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Source-Zermelo_ is a _source_ connector. The purpose of this connector is to import employees and their contacts with associated tasks and sections

### Endpoints

Currently the following endpoints are being used..

| Endpoint                     |
| ---------------------------- |
| api/v3/schools      |
| api/v3/sections      |
| api/v3/taskgroups      |
| api/v3/employees                 |
| api/v3/contracts     |
| api/v3/teacherteams      |
| api/v3/sectionassignments      |
| api/v3/sectionofbranches      |
| api/v3/branchesofschools      |
| api/v3/tasksinbranchofschool      |
| api/v3/taskassignments      ||

- The API documentation can be found at https://support.zermelo.nl/guides/developers-api

## Getting started

### Connection and configuration settings

The following settings are required to connect to the API.

| Setting    | Description                                                                            | Mandatory |
| ---------- | -------------------------------------------------------------------------------------- | --------- |
| BaseUrl    | The URL to the API                                                                     | Yes       |
| Token      | The token to authenticate to the Zermelo API | Yes|
| SchoolCode | The name of the school as known in Zermelo | Yes|
| CorrelationField| The name of the employee field that indentifies the user in Helloid. default "employeeNumber" | No |
| Compact    | When toggled, Tasks and Section with the same Start and End date are combined into the same contract| No |

### Remarks

- This is currently a source connector tailored to the requirements of a specific customer. While this can be used in general as a starting template for zermelo, you may need to implement more adjustments then usual to get it working at your location.

- The "CorrelationField" contains the name of the employee field that indentifies the user in Helloid. By default this is the "employeeNumber". This may however not be available (not filled correctly) in your envirionment. If it is available in an other field you have to specify the name of that field here. When using custom field, is assumed that this is in the format "#user_id#".
You may need to update the code if this is different in your environment.

- The different filter options of the Get calls are currently provided in the body of the request. This seems to work correctly, but it is customary to specify this in the url itself, so this may need some attention.

## Getting help

> ℹ️ _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> ℹ️ _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
