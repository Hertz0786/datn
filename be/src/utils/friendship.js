function normalizeFriendPair(userIdA, userIdB) {
  const first = userIdA.toString();
  const second = userIdB.toString();
  return first < second
    ? { userAId: first, userBId: second }
    : { userAId: second, userBId: first };
}

module.exports = {
  normalizeFriendPair,
};

