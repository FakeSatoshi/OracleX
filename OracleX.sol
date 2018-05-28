pragma solidity ^0.4.0;
contract Ownable {
  address public owner;
  
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function Ownable() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }
  
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


contract OracleX is Ownable{
    
/*-------LIBRARY CALLS-------*/

    using SafeMath for uint256; 

/*-------EVENTS-------*/

    event QueryPosted(uint queryId);
    event QueryContributed(uint queryId);
    event QueryLeaderChanged(uint queryId);
    event MoneyWithdrew(address _address,uint _amount);

/*-------PARAMETERS-------*/ 

    uint public minBounty=0.01 ether;
    uint public maxStakeMult=3;
        //uint public minVoteLength=86400;
    uint public minVoteLength=10;

/*-------MAPPINGS-------*/

        //The contract doesn't send ether directly to users unless they call a function themselves. 
        //Balances are kept in totalBalance and withdraw() can be called at any time from users to have their eth sent to their address
    mapping(address=>uint) public totalBalance;
    
        //queries[i] returns i+1th question
    uint nextQueryId;
    mapping(uint=>Query) public queries;

/*-------STRUCTURES-------*/

    struct Contribution {
        string answer;
        
            //maps addresses to the amount of eth they added to the Contribution 
        mapping(address=>uint) stakes;
        
            //timeAhead is the amount of time the contribution was ahead in votes
        uint timeAhead;
        
            //sum total of ether in stake for the contribution
        uint totalVotesContribution;
    }

    struct Query {
            //contributions maps answers to Contribution.
        mapping(string=>Contribution) contributions;
        
            //Set by query creator: Initial bounty, question, start time, end time and exampleAnswerFormat
        uint bounty;
        uint startTime;
        uint endTime;
        string question;
        string exampleAnswerFormat;
        
            //total amount of ether (votes+bounty)
        uint totalVotes;
        
            //answer with most ether staked since timeGotAhead
        string answerAhead;
        uint timeGotAhead;
        
            //answer that has been ahead the longest at timeGotAhead.
            //Is also the final winning answer once query has been finalized. If =="", then no answer has been given
        string answerAheadTime;
        
            //isFinalized is set to true once the query has been finalized
        bool isFinalized;
    }

/*-------MODIFIERS-------*/
    
        //makes sure query has not been finalized
    modifier notFinalized(uint _queryId) {
        require(!queries[_queryId].isFinalized);
        _;
    }

        //checks if bounty is larger than minBounty and a multiple of minMultiple
    modifier isValidBounty(uint _bounty) {
        require((_bounty>=minBounty)&&(msg.value>=_bounty));
        _;
    }
    
        //checks if start time and end time are valid
    modifier isValidTimes(uint _startTime,uint _endTime) {
        require((_endTime>_startTime.add(minVoteLength))&&(_startTime>now));
        _;
    }
    
        //checks for voting period
    modifier isOpenToVotes(uint _queryId){
        require((now>queries[_queryId].startTime)&&(now<queries[_queryId].endTime));
        _;    
    }
    
        //checks if voting period is over
    modifier isFinishedVotes(uint _queryId){
        require(now>queries[_queryId].endTime);
        _;      
    }

/*-------PUBLIC FUNCTIONS-------*/

        //Creates a query
    function createQuery(uint _startTime, uint _endTime, string _question,string _exampleAnswerFormat,uint _bounty) public payable isValidBounty(_bounty) isValidTimes(_startTime,_endTime){
        Query storage query=queries[nextQueryId];
        query.bounty=_bounty;
        query.startTime=_startTime;
        query.endTime=_endTime;
        query.question=_question;
        query.exampleAnswerFormat=_exampleAnswerFormat;
        query.totalVotes=_bounty;

        emit QueryPosted(nextQueryId);
        
            //donation to devs
        totalBalance[owner]+=(msg.value).sub(_bounty);
        
        nextQueryId++;
    }
    
        //Add a contribution
    function contribute(uint _queryId,string _answer) public payable isOpenToVotes(_queryId){
            //empty answer is not a valid contribution
        require(!isEmptyString(_answer));
        
            //0 is not an acceptable amount for a contribution
        require(msg.value>0);
        
            //stakable is the amount that can be staked on the contribution. It is <= msg.value 
        uint stakable=getStake(_queryId,_answer,msg.value);
     
            //deposit excess to balances and stake the rest (stakable)
        if(stakable<msg.value){
            totalBalance[msg.sender]+=msg.value.sub(stakable);
        }
        
        Query storage query=queries[_queryId];
        Contribution storage contribution=query.contributions[_answer];
        
            //adds your stake on the contribution, and updates totalVotes and totalVotesContribution
        contribution.stakes[msg.sender]+=stakable;
        contribution.totalVotesContribution+=stakable;
        query.totalVotes+=stakable;
        emit QueryContributed(_queryId);
        
            //set the leading answer if first contribution
        if(isEmptyString(query.answerAhead)){
            query.answerAhead=_answer;
            query.timeGotAhead=now;
            query.answerAheadTime=_answer;
        }
        else {
                //nothing more to do if leading contribution doesn't change
                //else, change leading contribution and add amount of time ahead to previous leader.
            if(keccak256(bytes(_answer))!=keccak256(bytes(query.answerAhead))){
                
                if (contribution.totalVotesContribution>query.contributions[query.answerAhead].totalVotesContribution){
                    
                    query.contributions[query.answerAhead].timeAhead+=now.sub(query.timeGotAhead);
                    
                        //if previous leader's (in votes) total time ahead is superior to previous timeAhead leader, then update answerAheadTime to previous leader. 
                    if(query.contributions[query.answerAhead].timeAhead>query.contributions[query.answerAheadTime].timeAhead) {
                        query.answerAheadTime=query.answerAhead;
                    }
                    
                    query.answerAhead=_answer;
                    query.timeGotAhead=now;
                    emit QueryLeaderChanged(_queryId);
                }    
            }
        }
    }
    
        //after endTime, anyone can finalize the Vote ie set winning answer.
    function finalizeVote(uint _queryId) public isFinishedVotes(_queryId) notFinalized(_queryId){
        Query storage query=queries[_queryId];
    
            //adds time from timeGotAhead, to end of voting period to the last contribution who was ahead
        query.contributions[query.answerAhead].timeAhead+=(query.endTime).sub(query.timeGotAhead);
        
            //Winner can only be answerAhead or answerAheadTime; checks which one has more time ahead and sets the new answerAheadTime
        if(query.contributions[query.answerAhead].timeAhead>query.contributions[query.answerAheadTime].timeAhead) {
            query.answerAheadTime=query.answerAhead;    
        }
        query.isFinalized=true;
        
            //if query has not been answered by anyone, no-one can claim the bounty and it goes to the devs.
        if(isEmptyString(query.answerAheadTime)){
            totalBalance[owner]+=query.bounty;
        }
    }
    
        //clameStakes is called by every individual voter to claim their staked ether and their part of the pool (bounty+non-winning stakes)
    function claimStakes(uint _queryId) public isFinishedVotes(_queryId){
        Query storage query=queries[_queryId];
        
            //if vote has not been finalized, finalize it in the same transaction.
        if(!query.isFinalized){finalizeVote(_queryId);}
        
            //No stakes to claim if no one has answered the question.
        require(!isEmptyString(query.answerAheadTime));
        
            //gets winning contribution
        Contribution storage contribution=query.contributions[query.answerAheadTime];
        
            //sets your stake to 0 and adds stake+winnings to your balance
            //if you staked a proportion x of the total ether staked on winning answer, your winnings are 
            //x*(bounty+total ether staked on losing answers)
        uint winningStake=contribution.stakes[msg.sender];
        contribution.stakes[msg.sender]=0;
        totalBalance[msg.sender]+=(winningStake.mul(query.totalVotes)).div(contribution.totalVotesContribution);
        
            //calls withdraw in same transaction
        withdraw();
    }
    
        //anyone can call withdraw() to withdraw their total balance. No partial withdrawals. 
        //transfer after updating totalBalance to prevent reentry from being effective 
        //even though transfer() should be safe...
    function withdraw() public {
        require(totalBalance[msg.sender]>0);
        uint amount=totalBalance[msg.sender];
        totalBalance[msg.sender]=0;
        msg.sender.transfer(amount);
        emit MoneyWithdrew(msg.sender,amount);
    }
    
    
/*-------INTERNAL FUNCTIONS-------*/

        //calculates the amount of eth to add to the contribution. If Contribution already maxed out, then throws.
        //If sent amount is too big, returns the max amount stakable
    function getStake(uint _queryId, string _answer, uint _sentAmount) internal view returns(uint){
        uint totalVotesContribution=queries[_queryId].contributions[_answer].totalVotesContribution;
        uint maxStakable=(((queries[_queryId].totalVotes).sub(totalVotesContribution)).mul(maxStakeMult)).sub(totalVotesContribution);
        require(maxStakable>0);
        return(min(maxStakable,_sentAmount));
    }
    
        //test for empty string
    function isEmptyString(string _answer) internal pure returns(bool){
        bytes memory tempEmptyStringTest = bytes(_answer); 
        return(tempEmptyStringTest.length == 0);
    }
    
    function min(uint a, uint b) internal pure returns (uint) {
        if (a < b) return a;
        else return b;
    }


/*-------PUBLIC VIEW FUNCTIONS-------*/

    function viewQuery(uint _queryId) public view returns(uint,uint,uint,string,string,uint,string,uint,string,bool){
        Query memory q=queries[_queryId];
        return(q.bounty,q.startTime,q.endTime,q.question,q.exampleAnswerFormat,q.totalVotes,q.answerAhead,q.timeGotAhead,q.answerAheadTime,q.isFinalized);
    }
    
    function totalNumberOfQueries() public view returns(uint){
        return(nextQueryId);
    }
    
}
/*-------LIBRARIES-------*/

    library SafeMath {
      function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
      }
     
      function div(uint256 a, uint256 b) internal pure returns (uint256) {
            // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
            // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
      }
     
      function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
      }
     
      function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
      }
    }    

    
    
