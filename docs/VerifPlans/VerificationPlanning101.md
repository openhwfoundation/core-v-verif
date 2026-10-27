<!--

 Copyright 2020, 2021 OpenHW Group
 Copyright 2026, Eclipse Foundation

 Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     https://solderpad.org/licenses/

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.

 SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0

-->

# What is a Verification Plan (Testplan)?
Verification plans are documents that define _what_ is to be verified, and _how_ it will be verified.
They go by many names including Testplan, DV plan or just Vplan.
A complete, high quality verification plan is one of the most valuable items produced by a verification project.

## Verification Planning
The purpose of a verification plan is to identify what features need to be verified; the success criteria of the feature and the coverage metrics for testing the feature.
Verification plans also allow us to reason about the capabilities of the testbench.
One way to think of a verification plan is that it is a laundry list of things to verify.
That is, we want a detailed list of **_what_** to verify.
A verification plan should also specify **_how_** each item (feature) in the list is to be verified.

## Format of a Verification Plan
Most CORE-V verification projects use spreadsheets to capture verification plans, and a template is provided.
The template for the spreadsheet is simple enough that you can use either Microsoft Office Excel, Google Sheets or LibreOffice Calc.
The verification plan [template](https://github.com/openhwgroup/core-v-verif/blob/master/docs/VerifPlans/templates/CORE-V_Simulation_VerifPlan_Template.xlsx) for CORE-V-VERIF is located at the root of the [VerificationPlan](https://github.com/openhwgroup/core-v-verif/tree/master/docs/VerifPlans) directory.
Note that OpenHW is also exploring the use of in-house tooling for Verification Planning, but the remainder of this document assumes the use of a spreadsheet.

## A Trivial Example: the RV32I ADDI Instruction
Let's assume your task is to verify a core's implementation of the RV32I ADDI instruction.
Simple right?
Create a simple assembler program with a few **_addi_** instructions, check the results, and we're done.
Unfortunately, simply checking for the correct result (rd = rs1 + imm) of a few instructions is insufficient.
On the other hand, exhaustively simulating all operand-value combinations is impractical.
A 32-bit source operand and a 12-bit immediate give 2^32 × 2^12 = 2^44 combinations, approximately 1.76 × 10^13.
Including all 32 source-register choices and all 32 destination-register choices gives a rough upper bound of 2^54,
approximately 1.80 × 10^16 test combinations, before accounting for constraints such as x0 always containing zero.

Obviously this is impractical and one of the things that makes Verification an art is determining the minimal amount of testing to have confidence that a feature is sufficiently tested.
Recognizing that the above are combinations of operand values and register choices, not distinct arithmetic results or instruction encodings,
allows us to make a few simplifying assumptions to reduce the problem to a manageable size.
For example we could say that addi is fully verified by covering the following cases:
* Use x0..x31 as rs1
* Use x0..x31 as rd (Note: the result of this operation will always be 0x00000000 when rd is x0)
* rd == rs1
* Set/Clear all bits of immediate
* Set/Clear all bits of rs1
* Set/Clear all bits of rd

You may see the above as overkill or underkill depending on your understanding of the micro-architecture or your level of risk aversion.
The point is, developing a verification plan forces you to consider your verification needs and plan accordingly.

## Features and Use Cases
When creating a verification plan for a specific feature, it is often helpful to consider three types of use-cases: success, edge and corner cases.

### Success Cases
_Success cases_ are 'typical use cases' for a specific feature.
In our addi example, 2+2=4 would be considered a success case.
Most features will have a large number of success cases and it is typically not required to test them all.

### Edge Cases
Almost every feature of the device-under-test (or DUT) will have a number of _edge cases_ that require special attention in your testplan.
In this document, an _edge case_ is a specific, documented scenario that has noticeably different behavior than a success case.
The edge cases for the RV32I ADDI instruction are:
1. Values of rs1 and imm that result in an overflow[^1].
2. Using x0 for rd.
3. Using x0 for rs1.
4. Using the same GPR for both rd and rs1.

[^1]: Note that in RISC-V integer instructions, overflows are not detected or stored.

### Corner Cases
_Corner cases_ are, by definition, very difficult to plan for.
Unlike success and edge cases, a corner case is not a behavior of the device that can be readily discerned by reading the specification.
As such, a typical verification plan will not have a lot of content related to corner cases.

# Using the CORE-V Simulation Verification Plan Template
The following sub-sections explain each of the columns in the [simulation verification template spreadsheet](https://github.com/openhwgroup/core-v-verif/blob/master/docs/VerifPlans/templates/CORE-V_Simulation_VerifPlan_Template.xlsx).

## Requirement Location
This is a pointer to the source Requirements document of the Features in question.
It can be a standards document, such as the RISC-V ISA, or a micro-architecture specification.
The CV32E40P [User Manual](https://cv32e40p.readthedocs.io/en/latest/intro/) lists sources of documentation relevant to the CV32E40P.
_Every item in a Verification Plan must be attributed to one or more of these sources_.
Please also include a chapter or section number.
Note that if you are using the [CV32E40P User Manual](https://core-v-docs-verif-strat.readthedocs.io/projects/cv32e40p_um/en/latest/) as a reference, you **must** provide a release/version number as well since this document is currently in active development.

## Feature
The high-level feature you are trying to verify.
For example, RV32I Register-Immediate Instructions.
In some cases, it may be natural to use the section header name of the reference document.

## Sub-Feature
This is an optional, but often used column.
Using our previous examples, ADDI is a sub-feature of RV32I Register-Immediate Instructions.
If it makes sense to decompose the Feature into two or more sub-features, use this column for that.
If required, add a column for sub-sub-features.

## Feature Description
A summary of what the feature does.
It should be a _summary_, not a verbatim copy-n-paste from the Requirements Document.

## Verification Goals
A summary of what stimulus and/or configuration needs to be generated/checked/covered to ensure sufficient testing of the Feature.
Recall the example of the _addi_ instruction.
The verification goals of that feature are:
* Unless rd is x0, rd gets the arithmetic sum of rs1 and the sign-extended immediate, otherwise it is 0x0.
* Overflow results in loss of MSB.
* No instruction execution side-effects (e.g. unexpected GPR changes, unexpected condition codes).
* Program counter increments by 0x4.

## Stimulus
Once the Verification Goals for a feature are understood, it is useful to think about the stimulus that will be required to achieve those goals.
Returning to our example we could say that addi is fully verified by covering the following cases:
* Use x0..x31 as rs1
* Use x0..x31 as rd
* Set/Clear all bits of immediate
* Set/Clear all bits of rs1

### Pass/Fail Criteria
#### What is Checked?
For every verification goal, there must be at least one check.
For the simple _addi_ instruction, several things must be checked:
1. The expected value of rd must be calculated and compared against the actual value produced by the device under test.
2. There shall be no instruction execution side-effects (e.g. unexpected GPR changes, unexpected condition codes).
3. Program counter increments by 0x4.

#### Check Method
Here we attempt to answer the question, "how will the testbench know the test passed?".
There are several methods that are typically used in CORE-V projects, and it is common to use more than one for a given item in a Verification Plan.
* **Self Checking**: A self-checking test-program encodes the correct result directly into the testcase and compares what the DUT does against this "known good" outcome.
  See the [RISCY Testcases](https://core-v-docs-verif-strat.readthedocs.io/en/latest/pulp_verif.html#ri5cy-testcases) section of the Verification Strategy for an example of this.
  This strategy is used extensively by the RISC-V International Architecture Certification Tests.
* **Signature Check**: This is a more sophisticated form of a self-checking test-program.
  The results of the test are used to calculate a signature and this is compared against a "known good" signature.
  This strategy is also used by the RISC-V International Architecture Certification tests.
* **Check against RM**: Here, the test-program does not "know" the correct output of the test.
  Instead, the pass/fail criteria is determined by a **_Reference Model_** (RM).
  An RM is a testbench component which models some or all of the DUT behavior.
  The testbench must compare the actual results from the DUT and the expected results from the RM.
  When practical, this is the preferred approach because it makes testcase maintenance simpler.
* **Assertion Check**: Failure is detected by an assertion, typically coded in SVA.
* **Any/All**: Any (or all) of the above pass/fail criteria can be reasonably assumed to catch a non-compliance of a specific feature/requirement.
* **Other**: If one of the above Pass/Fail Criteria does not fit your needs, specify it here.
* **N/A**: Select this for those (rare) features in the specification do not have side effects that are observable in a functional simulation of an RTL model.

### Test Type
Choose one or more of the following:
* **RISC-V Compliance**: a self-checking ISA certification testcase from RISC-V International.
* **Directed Self-Checking**: a directed (non-random) self-checking testcase from the OpenHW Group that is not specifically targetting ISA compliance.
* **Directed Non-Self-Checking**: a directed (non-random) non-self-checking testcase from the OpenHW Group that is not specifically targetting ISA compliance.
  Note that these tests assume that the pass/fail criteria will be "Check against ISS" (or other reference model).
* **Constrained-Random**: a constrained-random testcase.
  Typically the stimulus for these will come from the Google random instruction stream generator.
  Note that by definition these tests cannot be self-checking.
* **ENV capability, not specific test**: Often, a specific feature is not specifically covered by a specific test or check.
  For example, an assertion checking for bus protocol errors could reasonably expect to cause a failure with any type of test.
* **Other**: If one of the above Test Types does not fit your needs, specify it here.

### Coverage Method
How will we know that the Feature is verified (covered)?  There are several choices here:
* **Testcase:** if the testcase was run, the Feature was tested.
* **Functional Coverage:** the testbench supports SystemVerilog covergroups that measure stimulus/configuration/response conditions to show that the Feature was tested.
  **This is the preferred method of coverage.**
* **Assertion Coverage**: an alternate form of functional coverage, implemented as SVA cover properties.
* **Code Coverage:** the Feature is deemed to be tested when the specific conditions in the RTL have been exercised.

### Link to Coverage
This field is used to link the Feature to coverage data generated in Regression.
A non-tool-dependent technique to link your verification plan to coverage is to add SystemVerilog `option.comment` statements to your coverage model.

<!--
## HOWTO: The CORE-V Formal Verification Plan Template
The following sub-sections explain each of the columns in the [formal verification template spreadsheet](https://github.com/openhwgroup/core-v-verif/blob/master/docs/VerifPlans/templates/CORE-V_Formal_VerifPlan_Template.xlsx).
For obvious reasons, the **Requirement Location**, **Feature**, **Sub-Feature**, **Feature Description** and **Verification Goals** are the same as as the simulation verification template.
### Property or Checker
This is the name of the SystemVerilog _property_ or _checker_ that is used to verify the Feature in question.
Note that a _checker_ is typically a collection of properties and may also include "helper logic" in the form of synthesizable code.
### Type
The field defines how the property is to be used: either as an assertion (something that should never happen), coverage (something that should happen at least once) or an assumption (constraint).
### Result
Indicate whether the property or checker achieved a bounded or unbounded proof.
### Proof Depth
If an unbounded proof was not achieved, indicate the number of clock cycles analyzed for the bounded proof.

## Verification Plan Reviews
As core-v-verif is an open-source project it is necessary to enable open, comprehensive reviews with a broad set of stakeholders and interested parties in any proposed
Verification Plan.  At a minumum, design and verification leads, and related design engineers and verification engineers must be involved in a review.  The review should be
made open to all other interested contributors, utilizing collaboration tools as necessary.

Please use the following procedure when introducting a new verification plan or introducing a major edit to an existing Verification Plan.

1. The initial revision of the Verification Plan is created and added to the repository in a PR.  Note that the respective Verification Plan status page should always be up-to-date with current review status of the Vplan.
2. Create an Issue in core-v-verif https://github.com/openhwgroup/core-v-verif/issues/new/choose
   - The issue should be a Task
   - The issue should carry a core-specific label **if** the vplan is core-specific
   - The issue should have a link to the checked-in Vplan on GitHub.
   - The issue should be assigned to the Verification Plan Owner.
3. Arrange for a review call for the verification plan on Zoom, Teams or another appropriate platform.  Try to select a time to maximize attendance.
    - Add the following people as required attendees:
      - Verificaiton plan owner
      - Desiger responsbile for DUT feature being verified
      - Verification lead for project
4. Announce the verification plan review call and the Issue on Mattermost in the TWG: Verification channel.  Included a link to the meeting call.
5. Reviewers should pre-review the plan and provided comments in one of two ways.
    - (Preferable) directly annotate the spreadsheet via the comment mechanism in Excel and attach to the Issue when finished
    - Provided comments directly as comments on the GitHub issue
6. After the review meeting the Verification Plan Owner should incorporate feedback and apply a PR to update the plan.
7. Move the status in the README.md file accordingly to indiciate a reviewed plan

Note that a similar procedure should be followed for reviewing final vplan annotation after the vplan is fully executed.
--->
