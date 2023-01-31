const { inputToConfig } = require("@ethereum-waffle/compiler")
const { getNamedAccounts, deployments, ethers, network } = require("hardhat")
const { developmentChains, networkConfig } = require("../../helper-hardhat-config")
const { assert, expect } = require("chai")

developmentChains.includes(network.name)
    ? describe.skip
    : describe("Raffle", async function () {
          let raffle, raffleEntranceFee, deployer

          beforeEach(async function () {
              deployer = (await getNamedAccounts()).deployer
              raffle = await ethers.getContract("Raffle", deployer)
              raffleEntranceFee = await raffle.getEnteranceFee()
          })
          describe("fulfillRandomWords", function () {
              it("works with live Chainlink automation and Chainlink vrf, we get a random winner", async function () {
                  //enter raffle.
                  const staringTimeStamp = await raffle.getLatestTimeStamp()
                  const accounts = await ethers.getSigners()

                  await new Promise(async function (resolve, reject) {
                      //listener
                      // once the winner has been picked.
                      raffle.once("WinnerPicked", async function () {
                          console.log("WinnerPicked event has ben fired!")
                          try {
                              const recentWinner = await raffle.getRecentWinner()
                              const raffleState = await raffle.getRaffleState()
                              const winnerEndingBalance = await accounts[0].getBalance()
                              const endingTimeStamp = await raffle.getLatestTimeStamp()

                              await expect(raffle.getPlayer(0)).to.be.reverted //will be reverted because there's not an object at 0, it should have been reset.
                              assert.equal(recentWinner.toString(), accounts[0].address) //our deployer.
                              assert.equal(raffleState, 0) //we want to make sure the enum resets when we're done.
                              assert.equal(
                                  winnerEndingBalance.toString(),
                                  winnerStartingBalance.add(raffleEntranceFee).toString() //should get paid out the rafflEntranceFee (because they're the only one in the raffle the deployer.)
                              )
                              assert(endingTimeStamp > staringTimeStamp)
                              resolve() // if all of the above goes through, it'll return resolved.
                          } catch (error) {
                              console.log(error) // if we catch an error, we're going to reject the promise!
                              reject(e)
                          }
                      })
                      await raffle.enterRaffle({ value: raffleEntranceFee }) // entering the raffle.
                      //this code wont complete until our listener has finished listening!
                      const winnerStartingBalance = await accounts[0].getBalance()
                  })
              })
          })
      })
